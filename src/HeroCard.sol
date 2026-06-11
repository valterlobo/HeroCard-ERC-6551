// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/utils/Strings.sol";

import {ERC721Burnable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "./interfaces/IERC6551Registry.sol";
import "./interfaces/IERC6551Account.sol";

/// @title HeroCard
/// @notice Contrato ERC-721 de "Cartões Virtuais" com integração ERC-6551 (Token Bound Accounts)
///
/// @dev Cada HeroCard NFT possui uma Token Bound Account (TBA) associada que funciona
///      como uma carteira inteligente capaz de armazenar ETH, ERC-20, ERC-721 e ERC-1155.
///
///      ATENÇÃO IMPORTANTE:
///      - Transferir um HeroCard transfere AUTOMATICAMENTE o controle da TBA
///        e de TODOS os ativos que ela contém para o novo proprietário.
///      - Retire os ativos da TBA antes de transferir o NFT caso não queira
///        transferir o controle da carteira junto.
///
///      Roles:
///        DEFAULT_ADMIN_ROLE — administrador geral (pode conceder/revogar roles)
///        MINTER_ROLE        — pode mintar novos cartões
contract HeroCard is ERC721, ERC721URIStorage, ERC721Pausable, AccessControl, ERC721Burnable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // =========================================================================
    // Roles
    // =========================================================================

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // =========================================================================
    // Eventos
    // =========================================================================

    /// @notice Emitido quando um novo cartão é mintado
    event CardMinted(address indexed to, uint256 indexed tokenId);

    /// @notice Emitido quando uma TBA é criada para um cartão
    event TbaCreated(uint256 indexed tokenId, address indexed accountAddress);

    /// @notice Emitido quando ETH é depositado na TBA de um cartão
    event EthDeposited(uint256 indexed tokenId, address indexed from, uint256 amount);

    /// @notice Emitido quando tokens ERC-20 são depositados na TBA
    event Erc20Deposited(uint256 indexed tokenId, address indexed token, address indexed from, uint256 amount);

    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Endereço do registry ERC-6551
    IERC6551Registry public immutable registry;

    /// @notice Endereço da implementação da conta (ERC6551Account)
    address public immutable accountImplementation;

    /// @notice Contador de token IDs
    uint256 private _nextTokenId;

    /// @notice Salt padrão para criação de TBAs
    /// @dev Usando bytes32(0) como padrão; pode ser alterado por cartão se necessário
    bytes32 public constant DEFAULT_SALT = bytes32(0);

    // =========================================================================
    // Modificadores
    // =========================================================================

    /// @notice Garante que o chamador é o proprietário do NFT especificado
    modifier onlyOwnerOfToken(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "HeroCard: nao e o dono do cartao");
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @param _registry             Endereço do registry ERC-6551
    /// @param _accountImplementation Endereço da implementação ERC6551Account
    constructor(address _registry, address _accountImplementation) ERC721("HeroCard", "HERO") {
        require(_registry != address(0), "HeroCard: registry invalido");
        require(_accountImplementation != address(0), "HeroCard: implementation invalida");

        registry = IERC6551Registry(_registry);
        accountImplementation = _accountImplementation;

        // Concede roles ao deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // =========================================================================

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function safeMint(address to, uint256 tokenId, string memory uri) public onlyRole(MINTER_ROLE) {
        // Cria a TBA automaticamente no mint
        _createTba(tokenId);
        // Cria NFT e associa URI
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);

        emit CardMinted(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    //=====================================================================

    // =========================================================================
    // Mintagem
    // =========================================================================

    /// @notice Minta um novo HeroCard NFT e cria automaticamente sua TBA
    /// @param to       Endereço destinatário do NFT
    /// @param _tokenURI URI de metadados específica deste token (opcional)
    /// @return tokenId ID do token mintado
    function mint(address to, string calldata _tokenURI) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        safeMint(to, tokenId, _tokenURI);
    }

    /// @notice Minta em lote múltiplos HeroCards
    /// @param to        Endereço destinatário
    /// @param quantity  Quantidade de cartões a mintar
    /// @return firstId  ID do primeiro token mintado
    function mintBatch(address to, uint256 quantity) external onlyRole(MINTER_ROLE) returns (uint256 firstId) {
        require(quantity > 0 && quantity <= 50, "HeroCard: quantidade invalida");
        firstId = _nextTokenId;
        string memory _tokenURI;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId++;
            _tokenURI = string(abi.encodePacked("ipfs://QmHeroCard", Strings.toString(tokenId)));
            safeMint(to, tokenId, _tokenURI);
        }
    }

    // =========================================================================
    // Gerenciamento de TBA
    // =========================================================================

    /// @notice Retorna o endereço da TBA de um cartão (criada ou não)
    /// @param tokenId  ID do token NFT
    /// @param salt     Salt para cálculo do endereço (use DEFAULT_SALT = bytes32(0))
    /// @return         Endereço da TBA (pode ainda não ter código se não foi criada)
    function getAccount(uint256 tokenId, bytes32 salt) public view returns (address) {
        return registry.account(accountImplementation, salt, block.chainid, address(this), tokenId);
    }

    /// @notice Verifica se a TBA de um cartão já foi criada (tem código)
    /// @param tokenId  ID do token NFT
    /// @param salt     Salt utilizado na criação
    /// @return         true se a TBA existe (tem código deployado)
    function isAccountCreated(uint256 tokenId, bytes32 salt) public view returns (bool) {
        address tba = getAccount(tokenId, salt);
        return tba.code.length > 0;
    }

    /// @notice Cria a TBA de um cartão se ainda não existir
    /// @dev Qualquer pessoa pode chamar esta função (não apenas o owner)
    ///      pois criar a TBA é uma operação sem risco — o controle fica com o owner do NFT.
    /// @param tokenId  ID do token NFT
    /// @param salt     Salt para criação (use DEFAULT_SALT = bytes32(0))
    /// @return account Endereço da TBA (criada agora ou já existente)
    function createAccountIfNeeded(uint256 tokenId, bytes32 salt) external returns (address account) {
        _requireOwned(tokenId);

        if (isAccountCreated(tokenId, salt)) {
            return getAccount(tokenId, salt);
        }

        return _createTbaWithSalt(tokenId, salt);
    }

    // =========================================================================
    // Execução via TBA
    // =========================================================================

    /// @notice Executa uma chamada arbitrária pela TBA do cartão
    /// @dev Apenas o proprietário do NFT pode chamar esta função.
    ///      A TBA deve já ter sido criada.
    ///      Protegido contra reentrância.
    ///
    /// @param tokenId  ID do token NFT (cartão)
    /// @param to       Endereço de destino da chamada
    /// @param value    Valor ETH em wei a enviar
    /// @param data     Calldata da chamada
    /// @return result  Retorno da chamada executada
    function executeOnAccount(uint256 tokenId, address to, uint256 value, bytes calldata data)
        external
        payable
        nonReentrant
        onlyOwnerOfToken(tokenId)
        returns (bytes memory result)
    {
        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        result = IERC6551Executable(tba).execute{value: msg.value}(to, value, data, 0);
    }

    // =========================================================================
    // Depósito de Ativos na TBA
    // =========================================================================

    /// @notice Deposita ETH na TBA do cartão
    /// @param tokenId  ID do token NFT
    function depositEth(uint256 tokenId) external payable nonReentrant {
        _requireOwned(tokenId);
        require(msg.value > 0, "HeroCard: valor zero");

        // CEI: emit before external calls
        emit EthDeposited(tokenId, msg.sender, msg.value);

        address tba = _getOrCreateTba(tokenId);

        (bool success,) = tba.call{value: msg.value}("");
        require(success, "HeroCard: falha ao depositar ETH");
    }

    /// @notice Deposita tokens ERC-20 na TBA do cartão
    /// @dev O chamador deve ter aprovado este contrato para transferir os tokens.
    /// @param tokenId          ID do token NFT
    /// @param tokenContract    Endereço do contrato ERC-20
    /// @param amount           Quantidade de tokens a depositar
    function depositERC20(uint256 tokenId, address tokenContract, uint256 amount) external nonReentrant {
        _requireOwned(tokenId);
        require(amount > 0, "HeroCard: quantidade zero");

        // CEI: emit before external calls
        emit Erc20Deposited(tokenId, tokenContract, msg.sender, amount);

        address tba = _getOrCreateTba(tokenId);

        IERC20(tokenContract).safeTransferFrom(msg.sender, tba, amount);
    }

    /// @notice Deposita um NFT ERC-721 na TBA do cartão
    /// @dev O chamador deve ter aprovado este contrato para transferir o NFT.
    /// @param tokenId          ID do cartão (HeroCard)
    /// @param nftContract      Endereço do contrato ERC-721 a depositar
    /// @param nftTokenId       ID do NFT a depositar
    function depositERC721(uint256 tokenId, address nftContract, uint256 nftTokenId) external {
        _requireOwned(tokenId);
        address tba = _getOrCreateTba(tokenId);

        IERC721(nftContract).safeTransferFrom(msg.sender, tba, nftTokenId);
    }

    /// @notice Deposita tokens ERC-1155 na TBA do cartão
    /// @dev O chamador deve ter aprovado este contrato para transferir os tokens.
    /// @param tokenId          ID do cartão (HeroCard)
    /// @param tokenContract    Endereço do contrato ERC-1155
    /// @param assetTokenId     ID do token ERC-1155
    /// @param amount           Quantidade a depositar
    function depositERC1155(uint256 tokenId, address tokenContract, uint256 assetTokenId, uint256 amount) external {
        _requireOwned(tokenId);
        address tba = _getOrCreateTba(tokenId);

        IERC1155(tokenContract).safeTransferFrom(msg.sender, tba, assetTokenId, amount, "");
    }

    // =========================================================================
    // Saque de Ativos da TBA
    // =========================================================================

    /// @notice Saca ETH da TBA do cartão para o destinatário
    /// @param tokenId  ID do cartão
    /// @param to       Endereço destinatário
    /// @param amount   Valor ETH em wei a sacar
    function withdrawEth(uint256 tokenId, address payable to, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCard: destinatario invalido");
        require(amount > 0, "HeroCard: valor zero");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        // Executa transferência de ETH via TBA
        bytes memory result = IERC6551Executable(tba).execute(to, amount, "", 0);
        require(result.length == 0 || abi.decode(result, (bool)), "HeroCard: falha ao sacar ETH");
    }

    /// @notice Saca tokens ERC-20 da TBA do cartão
    /// @param tokenId          ID do cartão
    /// @param to               Endereço destinatário
    /// @param tokenContract    Endereço do contrato ERC-20
    /// @param amount           Quantidade de tokens a sacar
    function withdrawERC20(uint256 tokenId, address to, address tokenContract, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCard: destinatario invalido");
        require(amount > 0, "HeroCard: quantidade zero");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        // Encode da chamada transfer(to, amount) do ERC-20
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);

        bytes memory result = IERC6551Executable(tba).execute(tokenContract, 0, data, 0);
        require(result.length == 0 || abi.decode(result, (bool)), "HeroCard: falha ao sacar ERC20");
    }

    /// @notice Saca um NFT ERC-721 da TBA do cartão
    /// @param tokenId          ID do cartão
    /// @param to               Endereço destinatário
    /// @param nftContract      Endereço do contrato ERC-721
    /// @param nftTokenId       ID do NFT a sacar
    function withdrawERC721(uint256 tokenId, address to, address nftContract, uint256 nftTokenId)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCard: destinatario invalido");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        // safeTransferFrom is overloaded; use explicit selector for (address,address,uint256)
        bytes4 selector = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
        bytes memory data = abi.encodeWithSelector(selector, tba, to, nftTokenId);

        bytes memory result = IERC6551Executable(tba).execute(nftContract, 0, data, 0);
        require(result.length == 0 || abi.decode(result, (bool)), "HeroCard: falha ao sacar ERC721");
    }

    /// @notice Saca tokens ERC-1155 da TBA do cartão
    /// @param tokenId          ID do cartão
    /// @param to               Endereço destinatário
    /// @param tokenContract    Endereço do contrato ERC-1155
    /// @param assetTokenId     ID do token ERC-1155
    /// @param amount           Quantidade a sacar
    function withdrawERC1155(uint256 tokenId, address to, address tokenContract, uint256 assetTokenId, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCard: destinatario invalido");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        bytes memory data =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, tba, to, assetTokenId, amount, "");

        bytes memory result = IERC6551Executable(tba).execute(tokenContract, 0, data, 0);
        require(result.length == 0 || abi.decode(result, (bool)), "HeroCard: falha ao sacar ERC1155");
    }

    // =========================================================================
    // Administração
    // =========================================================================

    /// @notice Retorna o total de tokens mintados
    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
    }

    // =========================================================================
    // Override ERC165
    // =========================================================================

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // =========================================================================
    // Internos
    // =========================================================================

    /// @dev Cria a TBA com o salt padrão
    function _createTba(uint256 tokenId) internal returns (address) {
        return _createTbaWithSalt(tokenId, DEFAULT_SALT);
    }

    /// @dev Cria a TBA com salt específico e emite evento
    /// @dev registry é imutável e confiável; o endereço tba só está disponível após a chamada,
    ///      portanto reordenar com CEI não é estruturalmente possível aqui.
    ///
    /// @dev calls-inside-a-loop: a chamada externa ao registry é inevitável pois cada TBA
    ///      requer seu próprio tokenId para derivar um endereço CREATE2 único. O risco de DoS
    ///      é mitigado pelos seguintes fatores:
    ///        1. `registry` é `immutable` — definido no construtor, confiável por design.
    ///        2. O loop em mintBatch é limitado a no máximo 50 iterações.
    ///        3. `registry.createAccount` é idempotente — nunca reverte em chamadas duplicadas.
    // slither-disable-next-line reentrancy-events,calls-inside-a-loop
    function _createTbaWithSalt(uint256 tokenId, bytes32 salt) internal returns (address tba) {
        tba = registry.createAccount(accountImplementation, salt, block.chainid, address(this), tokenId);

        emit TbaCreated(tokenId, tba);
    }

    /// @dev Retorna o endereço da TBA, criando se necessário
    function _getOrCreateTba(uint256 tokenId) internal returns (address tba) {
        tba = getAccount(tokenId, DEFAULT_SALT);
        if (tba.code.length == 0) {
            tba = _createTba(tokenId);
        }
    }
}
