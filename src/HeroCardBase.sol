// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import {ERC721Pausable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";

import "./interfaces/IERC6551Registry.sol";
import "./interfaces/IERC6551Account.sol";

interface IHeroCardAccount {
    function executeWithSignature(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 deadline,
        bytes calldata signature
    ) external payable returns (bytes memory);
}

/// @title HeroCardBase
/// @notice Contrato ERC-721 abstrato base para "Cartões Virtuais" com integração ERC-6551 (Token Bound Accounts)
abstract contract HeroCardBase is ERC721, ERC721URIStorage, ERC721Pausable, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    event CardMinted(address indexed to, uint256 indexed tokenId);
    event TbaCreated(uint256 indexed tokenId, address indexed accountAddress);
    event EthDeposited(uint256 indexed tokenId, address indexed from, uint256 amount);
    event Erc20Deposited(uint256 indexed tokenId, address indexed token, address indexed from, uint256 amount);
    event EthWithdrawn(uint256 indexed tokenId, address indexed to, uint256 amount);
    event ERC20Withdrawn(uint256 indexed tokenId, address indexed token, address indexed to, uint256 amount);
    event ERC721Withdrawn(uint256 indexed tokenId, address indexed token, address indexed to, uint256 nftTokenId);
    event ERC1155Withdrawn(
        uint256 indexed tokenId, address indexed token, address indexed to, uint256 assetTokenId, uint256 amount
    );
    event ERC20ApprovalRevoked(uint256 indexed tokenId, address indexed token, address indexed spender);
    event ERC721OperatorRevoked(uint256 indexed tokenId, address indexed token, address indexed operator);
    event TargetAllowed(address indexed target, bool allowed);
    event AllowlistEnforced(bool enforced);

    uint256 private totalSupplyCounter;

    IERC6551Registry public immutable registry;
    address public immutable accountImplementation;
    bytes32 public constant DEFAULT_SALT = bytes32(0);

    bool public enforceAllowlist;
    mapping(address => bool) public allowedTargets;

    modifier onlyOwnerOfToken(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "HeroCard: nao e o dono do cartao");
        _;
    }

    modifier checkAllowlist(address to) {
        if (enforceAllowlist) {
            require(allowedTargets[to], "HeroCard: destino nao permitido");
        }
        _;
    }

    constructor(address _registry, address _accountImplementation, string memory _name, string memory _symbol)
        ERC721(_name, _symbol)
    {
        require(_registry != address(0), "HeroCard: registry invalido");
        require(_accountImplementation != address(0), "HeroCard: implementation invalida");
        require(_registry.code.length > 0, "HeroCard: registry deve ser contrato");
        require(_accountImplementation.code.length > 0, "HeroCard: implementation deve ser contrato");

        registry = IERC6551Registry(_registry);
        accountImplementation = _accountImplementation;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    /// @notice Pausa transferências e outras operações sensíveis do token.
    /// @dev Requer a role PAUSER_ROLE.
    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @notice Retoma o funcionamento normal do token.
    /// @dev Requer a role PAUSER_ROLE.
    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @notice Habilita ou desabilita a verificação de destinos (allowlist).
    /// @param _enforce Booleano indicando se a lista restrita de destinos está ativa.
    function setEnforceAllowlist(bool _enforce) external onlyRole(DEFAULT_ADMIN_ROLE) {
        enforceAllowlist = _enforce;
        emit AllowlistEnforced(_enforce);
    }

    /// @notice Adiciona ou remove um destino autorizado (para withdraws e executeOnAccount).
    /// @param target O endereço alvo.
    /// @param allowed True para permitir, false para revogar acesso.
    function setAllowedTarget(address target, bool allowed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allowedTargets[target] = allowed;
        emit TargetAllowed(target, allowed);
    }

    /// @notice Cria um novo token e vincula automaticamente uma TBA a ele.
    /// @param to Destinatário do novo token.
    /// @param tokenId O ID do token a ser criado.
    /// @param uri Metadados (URI) do token.
    function safeMint(address to, uint256 tokenId, string memory uri) public onlyRole(MINTER_ROLE) nonReentrant {
        _safeMint(to, tokenId);
        _createTba(tokenId);
        _setTokenURI(tokenId, uri);
        emit CardMinted(to, tokenId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        address previousOwner = super._update(to, tokenId, auth);

        if (previousOwner == address(0)) {
            totalSupplyCounter++;
        }
        if (to == address(0)) {
            totalSupplyCounter--;
        }

        return previousOwner;
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    /// @notice Atalho para criar um único token (chama safeMint internamente).
    /// @param to Destinatário do novo token.
    /// @param _tokenId O ID numérico do token.
    /// @param _tokenURI O metadado URI apontando para as propriedades do NFT.
    function mint(address to, uint256 _tokenId, string calldata _tokenURI) external onlyRole(MINTER_ROLE) {
        safeMint(to, _tokenId, _tokenURI);
    }

    /// @notice Cria diversos tokens para o mesmo destinatário em lote.
    /// @param to O destinatário dos tokens.
    /// @param tokenIds Lista com os IDs que serão criados.
    /// @param _tokenURIs Lista contendo a respectiva URI para cada tokenID.
    function mintBatch(address to, uint256[] memory tokenIds, string[] calldata _tokenURIs)
        external
        onlyRole(MINTER_ROLE)
    {
        uint256 quantity = tokenIds.length;
        require(quantity > 0 && quantity <= 50, "HeroCard: quantidade invalida");
        require(tokenIds.length == _tokenURIs.length, "HeroCard: quantidade de tokenIds e _tokenURIs deve ser igual");

        for (uint256 i = 0; i < quantity; i++) {
            for (uint256 j = i + 1; j < quantity; j++) {
                require(tokenIds[i] != tokenIds[j], "HeroCard: tokenIds duplicados");
            }
        }

        for (uint256 i = 0; i < quantity; i++) {
            safeMint(to, tokenIds[i], _tokenURIs[i]);
        }
    }

    /// @notice Retorna o endereço determinístico (ERC-6551) da TBA associada.
    /// @param tokenId ID do token alvo.
    /// @param salt Seed adicional para o address proxy (geralmente bytes32(0)).
    function getAccount(uint256 tokenId, bytes32 salt) public view returns (address) {
        return registry.account(accountImplementation, salt, block.chainid, address(this), tokenId);
    }

    /// @notice Confirma se o contrato proxy da conta já foi implantado no endereço estipulado.
    /// @param tokenId O ID do HeroCard associado.
    /// @param salt Salt com a qual a conta seria implantada.
    function isAccountCreated(uint256 tokenId, bytes32 salt) public view returns (bool) {
        address tba = getAccount(tokenId, salt);
        return tba.code.length > 0;
    }

    /// @notice Garante a implantação da conta TBA. Pode ser chamada se a conta falhou ao ser criada no mint inicial (fallback).
    /// @param tokenId ID numérico. O sender deve possuir o NFT para chamar esta função.
    /// @param salt Salt utilizada, que deve seguir o que se deseja.
    /// @return account O endereço do contrato TBA originado.
    function createAccountIfNeeded(uint256 tokenId, bytes32 salt) external returns (address account) {
        _requireOwned(tokenId);

        if (isAccountCreated(tokenId, salt)) {
            return getAccount(tokenId, salt);
        }

        return _createTbaWithSalt(tokenId, salt);
    }

    /// @notice Deposita ETH na TBA associada ao tokenId.
    /// @dev A TBA já deve existir (criada no mint ou via createAccountIfNeeded).
    ///      Qualquer endereço pode depositar ETH — isso é intencional para permitir
    ///      que terceiros financiem a TBA. Porém, a criação da TBA é restrita.
    function depositEth(uint256 tokenId) external payable nonReentrant {
        _requireOwned(tokenId);
        require(msg.value > 0, "HeroCard: valor zero");

        address tba = _getExistingTba(tokenId);

        emit EthDeposited(tokenId, msg.sender, msg.value);

        (bool success,) = tba.call{value: msg.value}("");
        require(success, "HeroCard: falha ao depositar ETH");
    }

    /// @notice Deposita ERC-20 na TBA associada ao tokenId.
    /// @dev A TBA já deve existir. Requer aprovação prévia do ERC-20.
    function depositERC20(uint256 tokenId, address tokenContract, uint256 amount) external nonReentrant {
        _requireOwned(tokenId);
        require(amount > 0, "HeroCard: quantidade zero");
        require(tokenContract.code.length > 0, "HeroCard: token deve ser contrato");

        address tba = _getExistingTba(tokenId);

        emit Erc20Deposited(tokenId, tokenContract, msg.sender, amount);

        IERC20(tokenContract).safeTransferFrom(msg.sender, tba, amount);
    }

    /// @notice Deposita ERC-721 na TBA associada ao tokenId.
    /// @dev A TBA já deve existir. Requer aprovação prévia do NFT.
    function depositERC721(uint256 tokenId, address nftContract, uint256 nftTokenId) external nonReentrant {
        _requireOwned(tokenId);
        require(nftContract.code.length > 0, "HeroCard: token deve ser contrato");
        address tba = _getExistingTba(tokenId);
        IERC721(nftContract).safeTransferFrom(msg.sender, tba, nftTokenId);
    }

    /// @notice Deposita ERC-1155 na TBA associada ao tokenId.
    /// @dev A TBA já deve existir. Requer aprovação prévia do token.
    function depositERC1155(uint256 tokenId, address tokenContract, uint256 assetTokenId, uint256 amount)
        external
        nonReentrant
    {
        _requireOwned(tokenId);
        require(tokenContract.code.length > 0, "HeroCard: token deve ser contrato");
        address tba = _getExistingTba(tokenId);
        IERC1155(tokenContract).safeTransferFrom(msg.sender, tba, assetTokenId, amount, "");
    }

    // =========================================================================
    // Meta-Transactions (Wrapper)
    // =========================================================================
    // Nota de Design: A operação `executeBatch` é exposta diretamente pela TBA
    // (Token Bound Account). Não oferecemos um wrapper `executeBatchOnAccount` aqui
    // em HeroCardBase. Isso é uma escolha de design ("TBA-only"): chamadas em lote
    // devem ser feitas diretamente interagindo com o contrato da TBA.
    // =========================================================================

    /// @notice Executa uma chamada genérica na TBA do token usando assinatura.
    /// @param tokenId ID do HeroCard dono da TBA.
    /// @param to Endereço de destino da chamada.
    /// @param value Valor em wei a ser enviado.
    /// @param data Payload da chamada.
    /// @param operation Tipo da operação (0 = CALL).
    /// @param signature Assinatura digital válida do owner atual do NFT.
    /// @return Retorno da chamada.
    function executeOnAccount(
        uint256 tokenId,
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant checkAllowlist(to) returns (bytes memory) {
        _requireOwned(tokenId);

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao existe");

        return
            IHeroCardAccount(tba).executeWithSignature{value: msg.value}(
                to, value, data, operation, deadline, signature
            );
    }

    /// @notice Saca ETH nativamente da TBA.
    /// @param tokenId ID do cartão de origem.
    /// @param to Recebedor do ETH sendo retirado.
    /// @param amount Quantidade em WEI de ETH sendo extraída.
    /// @param signature Assinatura criptográfica que atesta e autoriza a operação.
    function withdrawEth(uint256 tokenId, address to, uint256 amount, uint256 deadline, bytes calldata signature)
        external
        nonReentrant
        checkAllowlist(to)
    {
        _requireOwned(tokenId);
        require(to != address(0), "HeroCard: endereco destino invalido");
        address tba = getAccount(tokenId, DEFAULT_SALT);
        // Retorno ignorado: falhas propagadas como revert por executeWithSignature
        IHeroCardAccount(tba).executeWithSignature(to, amount, "", 0, deadline, signature);
        emit EthWithdrawn(tokenId, to, amount);
    }

    /// @notice Saca tokens ERC-20 da TBA para a conta designada.
    /// @param tokenId ID numérico do NFT.
    /// @param token Contrato do ERC-20.
    /// @param to Conta recebedora dos ativos transferidos da TBA.
    /// @param amount Quantidade repassada.
    /// @param signature Assinatura do autorizador/dono.
    function withdrawERC20(
        uint256 tokenId,
        address token,
        address to,
        uint256 amount,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant checkAllowlist(to) {
        _requireOwned(tokenId);
        require(to != address(0), "HeroCard: endereco destino invalido");
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, deadline, signature);
        emit ERC20Withdrawn(tokenId, token, to, amount);
    }

    /// @notice Executa safeTransferFrom de um ERC-721 pertencente à TBA.
    /// @param tokenId ID numérico principal (HeroCard).
    /// @param token Contrato do ERC-721 que está na TBA.
    /// @param to Destinatário do ativo.
    /// @param nftTokenId ID do ERC-721 sendo retirado.
    /// @param signature Assinatura validadora.
    function withdrawERC721(
        uint256 tokenId,
        address token,
        address to,
        uint256 nftTokenId,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant checkAllowlist(to) {
        _requireOwned(tokenId);
        require(to != address(0), "HeroCard: endereco destino invalido");
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data =
            abi.encodeWithSelector(bytes4(keccak256("safeTransferFrom(address,address,uint256)")), tba, to, nftTokenId);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, deadline, signature);
        emit ERC721Withdrawn(tokenId, token, to, nftTokenId);
    }

    /// @notice Executa safeTransferFrom de ERC-1155 pertencente à TBA.
    /// @param tokenId O ID referente ao HeroCard principal.
    /// @param token Endereço do ativo ERC-1155 a ser sacado.
    /// @param to Destinatário final.
    /// @param assetTokenId O id correspondente ao ativo ERC-1155.
    /// @param amount O valor (quantidade) extraído.
    /// @param data Contexto adicional exigido pela função safeTransferFrom.
    /// @param signature A assinatura validadora (owner do HeroCard).
    function withdrawERC1155(
        uint256 tokenId,
        address token,
        address to,
        uint256 assetTokenId,
        uint256 amount,
        uint256 deadline,
        bytes calldata data,
        bytes calldata signature
    ) external nonReentrant checkAllowlist(to) {
        _requireOwned(tokenId);
        require(to != address(0), "HeroCard: endereco destino invalido");
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory callData =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, tba, to, assetTokenId, amount, data);
        IHeroCardAccount(tba).executeWithSignature(token, 0, callData, 0, deadline, signature);
        emit ERC1155Withdrawn(tokenId, token, to, assetTokenId, amount);
    }

    /// @notice Interrompe aprovações (approve) de ERC-20 dadas pela TBA para um dado spender (zera a permissão).
    /// @param tokenId ID responsável (HeroCard).
    /// @param token O contrato do token ERC-20.
    /// @param spender O endereço cujo allowance será definido para zero.
    /// @param signature Assinatura do owner autorizando.
    function revokeERC20Approvals(
        uint256 tokenId,
        address token,
        address spender,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spender, 0);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, deadline, signature);
        emit ERC20ApprovalRevoked(tokenId, token, spender);
    }

    /// @notice Interrompe a autoridade fornecida por setApprovalForAll (ERC-721/1155) pela TBA a um dado operator.
    /// @param tokenId ID do HeroCard correspondente.
    /// @param token Contrato cujas aprovações serão interrompidas.
    /// @param operator A conta que perderá os direitos.
    /// @param signature Assinatura do owner autorizando.
    function revokeERC721Operators(
        uint256 tokenId,
        address token,
        address operator,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data = abi.encodeWithSelector(IERC721.setApprovalForAll.selector, operator, false);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, deadline, signature);
        emit ERC721OperatorRevoked(tokenId, token, operator);
    }

    /// @notice Retorna a contagem atual de HeroCards emitidos que não foram queimados.
    /// @return O totalSupply vigente (quantidade de cartões válidos em circulação).
    function totalSupply() external view returns (uint256) {
        return totalSupplyCounter;
    }

    /// @notice Recupera tokens ERC-20 transferidos por engano diretamente para este contrato base (não para uma TBA).
    /// @dev Apenas DEFAULT_ADMIN_ROLE pode utilizar e resgatar.
    /// @param token Endereço do contrato do token que foi enviado por erro.
    /// @param to Destino de recuperação.
    /// @param amount Quantia a ser resgatada.
    function rescueERC20(address token, address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(to != address(0), "HeroCard: endereco destino invalido");
        IERC20(token).safeTransfer(to, amount);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    function _createTba(uint256 tokenId) internal returns (address) {
        return _createTbaWithSalt(tokenId, DEFAULT_SALT);
    }

    function _createTbaWithSalt(uint256 tokenId, bytes32 salt) internal returns (address tba) {
        tba = registry.createAccount(accountImplementation, salt, block.chainid, address(this), tokenId);
        emit TbaCreated(tokenId, tba);
    }

    /// @notice Retorna o endereço da TBA existente ou reverte se não foi criada.
    /// @dev Previne que terceiros forcem a criação de TBAs via funções de depósito.
    ///      A TBA deve ter sido criada previamente via mint ou createAccountIfNeeded.
    function _getExistingTba(uint256 tokenId) internal view returns (address tba) {
        tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao existe");
    }
}
