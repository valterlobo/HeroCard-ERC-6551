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

    IERC6551Registry public immutable registry;
    address public immutable accountImplementation;
    string public baseUriPrefix;

    uint256 private _nextTokenId;
    bytes32 public constant DEFAULT_SALT = bytes32(0);

    modifier onlyOwnerOfToken(uint256 tokenId) {
        require(ownerOf(tokenId) == msg.sender, "HeroCard: nao e o dono do cartao");
        _;
    }

    constructor(
        address _registry,
        address _accountImplementation,
        string memory _name,
        string memory _symbol,
        string memory _baseUriPrefix
    ) ERC721(_name, _symbol) {
        require(_registry != address(0), "HeroCard: registry invalido");
        require(_accountImplementation != address(0), "HeroCard: implementation invalida");

        registry = IERC6551Registry(_registry);
        accountImplementation = _accountImplementation;
        baseUriPrefix = _baseUriPrefix;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    function pause() public onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function safeMint(address to, uint256 tokenId, string memory uri) public onlyRole(MINTER_ROLE) nonReentrant {
        _createTba(tokenId);
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, uri);
        emit CardMinted(to, tokenId);
    }

    function _update(address to, uint256 tokenId, address auth)
        internal
        virtual
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function mint(address to, string calldata _tokenURI) external onlyRole(MINTER_ROLE) returns (uint256 tokenId) {
        tokenId = _nextTokenId++;
        safeMint(to, tokenId, _tokenURI);
    }

    function mintBatch(address to, uint256 quantity) external onlyRole(MINTER_ROLE) returns (uint256 firstId) {
        require(quantity > 0 && quantity <= 50, "HeroCard: quantidade invalida");
        firstId = _nextTokenId;
        string memory _tokenURI;

        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _nextTokenId++;
            _tokenURI = string(abi.encodePacked(baseUriPrefix, Strings.toString(tokenId)));
            safeMint(to, tokenId, _tokenURI);
        }
    }

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

    function depositEth(uint256 tokenId) external payable nonReentrant {
        _requireOwned(tokenId);
        require(msg.value > 0, "HeroCard: valor zero");

        address tba = _getOrCreateTba(tokenId);

        emit EthDeposited(tokenId, msg.sender, msg.value);

        (bool success,) = tba.call{value: msg.value}("");
        require(success, "HeroCard: falha ao depositar ETH");
    }

    function depositERC20(uint256 tokenId, address tokenContract, uint256 amount) external nonReentrant {
        _requireOwned(tokenId);
        require(amount > 0, "HeroCard: quantidade zero");

        address tba = _getOrCreateTba(tokenId);

        emit Erc20Deposited(tokenId, tokenContract, msg.sender, amount);

        IERC20(tokenContract).safeTransferFrom(msg.sender, tba, amount);
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

    function withdrawEth(uint256 tokenId, address payable to, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCard: destinatario invalido");
        require(amount > 0, "HeroCard: valor zero");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        bytes memory result = IERC6551Executable(tba).execute(to, amount, "", 0);
        require(
            result.length == 0 || (result.length == 32 && abi.decode(result, (bool))), "HeroCard: falha ao sacar ETH"
        );
    }

    function withdrawERC20(uint256 tokenId, address to, address tokenContract, uint256 amount)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCard: destinatario invalido");
        require(amount > 0, "HeroCard: quantidade zero");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);

        bytes memory result = IERC6551Executable(tba).execute(tokenContract, 0, data, 0);

        require(
            result.length == 0 || (result.length == 32 && abi.decode(result, (bool))), "HeroCard: falha ao sacar ERC20"
        );
    }

    function withdrawERC721(uint256 tokenId, address to, address nftContract, uint256 nftTokenId)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(to != address(0), "HeroCard: destinatario invalido");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        bytes4 selector = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
        bytes memory data = abi.encodeWithSelector(selector, tba, to, nftTokenId);
        bytes memory result = IERC6551Executable(tba).execute(nftContract, 0, data, 0);
        require(
            result.length == 0 || (result.length == 32 && abi.decode(result, (bool))), "HeroCard: falha ao sacar ERC721"
        );
    }

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
        require(
            result.length == 0 || (result.length == 32 && abi.decode(result, (bool))),
            "HeroCard: falha ao sacar ERC1155"
        );
    }

    function revokeERC20Approvals(uint256 tokenId, address[] calldata tokens, address[] calldata spenders)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(tokens.length == spenders.length, "HeroCard: arrays de tamanho diferente");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        for (uint256 i = 0; i < tokens.length; i++) {
            bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spenders[i], 0);
            bytes memory result = IERC6551Executable(tba).execute(tokens[i], 0, data, 0);
            require(
                result.length == 0 || (result.length == 32 && abi.decode(result, (bool))),
                "HeroCard: falha ao revogar ERC20"
            );
        }
    }

    function revokeERC721Operators(uint256 tokenId, address[] calldata contracts, address[] calldata operators)
        external
        nonReentrant
        onlyOwnerOfToken(tokenId)
    {
        require(contracts.length == operators.length, "HeroCard: arrays de tamanho diferente");

        address tba = getAccount(tokenId, DEFAULT_SALT);
        require(tba.code.length > 0, "HeroCard: TBA nao criada");

        for (uint256 i = 0; i < contracts.length; i++) {
            bytes memory data = abi.encodeWithSelector(IERC721.setApprovalForAll.selector, operators[i], false);
            bytes memory result = IERC6551Executable(tba).execute(contracts[i], 0, data, 0);
            require(
                result.length == 0 || (result.length == 32 && abi.decode(result, (bool))),
                "HeroCard: falha ao revogar ERC721"
            );
        }
    }

    function totalSupply() external view returns (uint256) {
        return _nextTokenId;
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

    function _getOrCreateTba(uint256 tokenId) internal returns (address tba) {
        tba = getAccount(tokenId, DEFAULT_SALT);
        if (tba.code.length == 0) {
            tba = _createTba(tokenId);
        }
    }
}
