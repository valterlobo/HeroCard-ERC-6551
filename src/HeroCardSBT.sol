// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
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

/// @title HeroCardSBT
/// @notice Contrato ERC-721 Soulbound (Não-transferível) de "Cartões Virtuais" com integração ERC-6551 (Token Bound Accounts)
///
/// @dev Cada HeroCardSBT NFT possui uma Token Bound Account (TBA) associada que funciona
///      como uma carteira inteligente capaz de armazenar ETH, ERC-20, ERC-721 e ERC-1155.
///
///      DIFERENÇA PARA O HEROCARD ORIGINAL:
///      Este contrato é um Soulbound Token (SBT), o que significa que, uma vez mintado
///      para um endereço, ele NÃO pode ser transferido para outro. As únicas transferências
///      permitidas são de mint (criação) e burn (destruição).
///
///      Roles:
///        DEFAULT_ADMIN_ROLE — administrador geral (pode conceder/revogar roles)
///        MINTER_ROLE        — pode mintar novos cartões
contract HeroCardSBT is ERC721, ERC721URIStorage, ERC721Pausable, AccessControl, ReentrancyGuard {
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
    bytes32 public constant DEFAULT_SALT = bytes32(0);

    // =========================================================================
    // Modificadores
    // =========================================================================

    /// @notice Garante que o chamador é o proprietário do NFT especificado
    modifier onlyOwnerOfToken(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "HeroCardSBT: nao e o dono do cartao");
        _;
    }

    // =========================================================================
    // Constructor
    // =========================================================================

    /// @param _registry             Endereço do registry ERC-6551
    /// @param _accountImplementation Endereço da implementação ERC6551Account
    constructor(address _registry, address _accountImplementation) ERC721("HeroCardSBT", "HSBT") {
        require(_registry != address(0), "HeroCardSBT: registry invalido");
        require(_accountImplementation != address(0), "HeroCardSBT: implementation invalida");

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

    function safeMint(address to, uint256 tokenId, string memory uri) public onlyRole(MINTER_ROLE) nonReentrant {
        _createTba(tokenId); // Cria a TBA primeiro
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        emit CardMinted(to, tokenId);
    }

    // The following functions are overrides required by Solidity.

    /// @dev Sobrescreve a função de atualização de propriedade para tornar o token Soulbound (intransferível)
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        address from = _ownerOf(tokenId);
        
        // Se `from` não for 0 (não é mint) e `to` não for 0 (não é burn), então é uma transferência.
        // Revertemos, pois SBTs não podem ser transferidos.
        require(from == address(0) || to == address(0), "HeroCardSBT: Transferencia nao permitida (Soulbound)");

        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    // =========================================================================
    // Mintagem
    // =========================================================================

    /// @notice Minta um novo HeroCard SBT e cria automaticamente sua TBA
    function mint(address to, string calldata _tokenURI) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        safeMint(to, tokenId, _tokenURI);
    }

    /// @notice Minta em lote múltiplos HeroCard SBTs
    function mintBatch(address to, uint256 quantity) external onlyRole(MINTER_ROLE) returns (uint256 firstId) {
        require(quantity > 0 && quantity <= 50, "HeroCardSBT: quantidade invalida");
        firstId = _nextTokenId;
        string memory _tokenURI;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId++;
            _tokenURI = string(abi.encodePacked("ipfs://QmHeroCardSBT", Strings.toString(tokenId)));
            safeMint(to, tokenId, _tokenURI);
        }
    }

    // =========================================================================
    // Gerenciamento de TBA
    // =========================================================================

    function getAccount(uint256 tokenId, bytes32 salt) public view returns (address) {
        return registry.account(accountImplementation, salt, block.chainid, address(this), tokenId);
    }

    function isAccountCreated(uint256 tokenId, bytes32 salt) public view returns (bool) {
        address tba = getAccount(tokenId, salt);
        return tba.code.length > 0;
    }

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

    function executeOnAccount(uint256 tokenId, address to, uint256 value, bytes calldata data)
        external
        payable
        nonReentrant
        onlyOwnerOfToken(tokenId)
        returns (bytes memory result)
    {
        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCardSBT: TBA nao criada");

        result = IERC6551Executable(tba).execute{value: msg.value}(to, value, data, 0);
    }

    // =========================================================================
    // Depósito de Ativos na TBA
    // =========================================================================

    function depositEth(uint256 tokenId) external payable nonReentrant {
        _requireOwned(tokenId);
        require(msg.value > 0, "HeroCardSBT: valor zero");

        address tba = _getOrCreateTba(tokenId);

        (bool success,) = tba.call{value: msg.value}("");
        require(success, "HeroCardSBT: falha ao depositar ETH");

        emit EthDeposited(tokenId, msg.sender, msg.value);
    }

    function depositERC20(uint256 tokenId, address tokenContract, uint256 amount) external nonReentrant {
        _requireOwned(tokenId);
        require(amount > 0, "HeroCardSBT: quantidade zero");

        address tba = _getOrCreateTba(tokenId);

        IERC20(tokenContract).safeTransferFrom(msg.sender, tba, amount);

        emit Erc20Deposited(tokenId, tokenContract, msg.sender, amount);
    }

    function depositERC721(uint256 tokenId, address nftContract, uint256 nftTokenId) external nonReentrant {
        _requireOwned(tokenId);
        address tba = _getOrCreateTba(tokenId);
        IERC721(nftContract).safeTransferFrom(msg.sender, tba, nftTokenId);
    }

    function depositERC1155(uint256 tokenId, address tokenContract, uint256 assetTokenId, uint256 amount)
        external
        nonReentrant
    {
        _requireOwned(tokenId);
        address tba = _getOrCreateTba(tokenId);
        IERC1155(tokenContract).safeTransferFrom(msg.sender, tba, assetTokenId, amount, "");
    }

    // =========================================================================
    // Saque de Ativos da TBA
    // =========================================================================

    function withdrawEth(uint256 tokenId, address payable to, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCardSBT: destinatario invalido");
        require(amount > 0, "HeroCardSBT: valor zero");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCardSBT: TBA nao criada");

        bytes memory result = IERC6551Executable(tba).execute(to, amount, "", 0);
        require(result.length == 0 || abi.decode(result, (bool)), "HeroCardSBT: falha ao sacar ETH");
    }

    function withdrawERC20(uint256 tokenId, address to, address tokenContract, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCardSBT: destinatario invalido");
        require(amount > 0, "HeroCardSBT: quantidade zero");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCardSBT: TBA nao criada");

        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        bytes memory result = IERC6551Executable(tba).execute(tokenContract, 0, data, 0);

        require(
            result.length == 0 || (result.length == 32 && abi.decode(result, (bool))), "HeroCardSBT: falha ao sacar ERC20"
        );
    }

    function withdrawERC721(uint256 tokenId, address to, address nftContract, uint256 nftTokenId)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCardSBT: destinatario invalido");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCardSBT: TBA nao criada");

        bytes4 selector = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
        bytes memory data = abi.encodeWithSelector(selector, tba, to, nftTokenId);
        bytes memory result = IERC6551Executable(tba).execute(nftContract, 0, data, 0);
        require(result.length == 0 || abi.decode(result, (bool)), "HeroCardSBT: falha ao sacar ERC721");
    }

    function withdrawERC1155(uint256 tokenId, address to, address tokenContract, uint256 assetTokenId, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCardSBT: destinatario invalido");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCardSBT: TBA nao criada");

        bytes memory data =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, tba, to, assetTokenId, amount, "");

        bytes memory result = IERC6551Executable(tba).execute(tokenContract, 0, data, 0);
        require(result.length == 0 || abi.decode(result, (bool)), "HeroCardSBT: falha ao sacar ERC1155");
    }

    // =========================================================================
    // Administração
    // =========================================================================

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

    function _createTba(uint256 tokenId) internal returns (address) {
        return _createTbaWithSalt(tokenId, DEFAULT_SALT);
    }

    // slither-disable-next-line reentrancy-events,calls-inside-a-loop
    function _createTbaWithSalt(uint256 tokenId, bytes32 salt) internal returns (address tba) {
        tba = registry.createAccount(accountImplementation, salt, block.chainid, address(this), tokenId);
        emit TbaCreated(tokenId, tba);
    }

    function _getOrCreateTba(uint256 tokenId) internal returns (address tba) {
        tba = getAccount(tokenId, DEFAULT_SALT);
        if (tba.code.length == 0) {
            tba = _createTba(tokenId);
        }
    }
}
