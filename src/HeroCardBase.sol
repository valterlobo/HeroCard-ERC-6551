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

    // =========================================================================
    // Meta-Transactions (Wrapper)
    // =========================================================================

    function executeOnAccount(
        uint256 tokenId,
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        bytes calldata signature
    ) external payable nonReentrant returns (bytes memory) {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);

        return IHeroCardAccount(tba).executeWithSignature{value: msg.value}(to, value, data, operation, signature);
    }

    function withdrawEth(uint256 tokenId, address to, uint256 amount, bytes calldata signature) external nonReentrant {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        IHeroCardAccount(tba).executeWithSignature(to, amount, "", 0, signature);
    }

    function withdrawERC20(uint256 tokenId, address token, address to, uint256 amount, bytes calldata signature)
        external
        nonReentrant
    {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data = abi.encodeWithSelector(IERC20.transfer.selector, to, amount);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, signature);
    }

    function withdrawERC721(uint256 tokenId, address token, address to, uint256 nftTokenId, bytes calldata signature)
        external
        nonReentrant
    {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data =
            abi.encodeWithSelector(bytes4(keccak256("safeTransferFrom(address,address,uint256)")), tba, to, nftTokenId);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, signature);
    }

    function withdrawERC1155(
        uint256 tokenId,
        address token,
        address to,
        uint256 assetTokenId,
        uint256 amount,
        bytes calldata data,
        bytes calldata signature
    ) external nonReentrant {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory callData =
            abi.encodeWithSelector(IERC1155.safeTransferFrom.selector, tba, to, assetTokenId, amount, data);
        IHeroCardAccount(tba).executeWithSignature(token, 0, callData, 0, signature);
    }

    function revokeERC20Approvals(uint256 tokenId, address token, address spender, bytes calldata signature)
        external
        nonReentrant
    {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data = abi.encodeWithSelector(IERC20.approve.selector, spender, 0);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, signature);
    }

    function revokeERC721Operators(uint256 tokenId, address token, address operator, bytes calldata signature)
        external
        nonReentrant
    {
        _requireOwned(tokenId);
        address tba = getAccount(tokenId, DEFAULT_SALT);
        bytes memory data = abi.encodeWithSelector(IERC721.setApprovalForAll.selector, operator, false);
        IHeroCardAccount(tba).executeWithSignature(token, 0, data, 0, signature);
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
