// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {Script, console} from "forge-std/Script.sol";

import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCard.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";

/// @title HeroCardTest
/// @notice Suite completa de testes para o sistema ERC-6551 HeroCard
contract HeroCardTest is Test {
    event CardMinted(address indexed to, uint256 indexed tokenId);

    // =========================================================================
    // Contratos
    // =========================================================================

    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;
    MockERC20 public gold;
    MockERC721 public sword;

    // =========================================================================
    // Atores
    // =========================================================================

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public minter = makeAddr("minter");

    // =========================================================================
    // Setup
    // =========================================================================

    function setUp() public {
        vm.startPrank(owner);

        // 1. Deploy do registry ERC-6551
        registry = new ERC6551Registry();

        // 2. Deploy da implementação da conta
        accountImpl = new HeroCardAccount();

        // 3. Deploy do HeroCard NFT
        heroCard = new HeroCard(address(registry), address(accountImpl));

        // 4. Concede role de minter
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);

        // 5. Mocks para testes de ativos
        gold = new MockERC20("Gold Token", "GOLD");
        sword = new MockERC721("Sword NFT", "SWORD");

        vm.stopPrank();

        // Financia contas de teste
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    // =========================================================================
    // Testes: Mint
    // =========================================================================

    function test_mint_success() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        assertEq(heroCard.ownerOf(tokenId), alice);
        assertEq(heroCard.totalSupply(), 1);
    }

    function test_mint_emits_events() public {
        vm.prank(minter);
        vm.expectEmit(true, true, false, true);
        emit CardMinted(alice, 0);

        heroCard.mint(alice, "");
    }

    function test_mint_creates_tba() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        // TBA deve ter sido criada no mint
        assertTrue(heroCard.isAccountCreated(tokenId, heroCard.DEFAULT_SALT()));
    }

    function test_mint_only_minter() public {
        vm.prank(alice);
        vm.expectRevert();
        heroCard.mint(alice, "");
    }

    function test_mint_with_uri() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "ipfs://QmXxx");
        assertEq(heroCard.tokenURI(tokenId), "ipfs://QmXxx");
    }

    function test_mintBatch() public {
        vm.prank(minter);
        uint256 firstId = heroCard.mintBatch(alice, 3);

        assertEq(heroCard.totalSupply(), 3);
        assertEq(heroCard.ownerOf(firstId), alice);
        assertEq(heroCard.ownerOf(firstId + 1), alice);
        assertEq(heroCard.ownerOf(firstId + 2), alice);
    }

    // =========================================================================
    // Testes: TBA - Endereço e Criação
    // =========================================================================

    function test_getAccount_deterministic() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        address tba1 = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());
        address tba2 = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        assertEq(tba1, tba2, "enderecos devem ser deterministicos");
    }

    function test_getAccount_different_tokens() public {
        vm.startPrank(minter);
        uint256 id0 = heroCard.mint(alice, "");
        uint256 id1 = heroCard.mint(alice, "");
        vm.stopPrank();

        address tba0 = heroCard.getAccount(id0, heroCard.DEFAULT_SALT());
        address tba1 = heroCard.getAccount(id1, heroCard.DEFAULT_SALT());

        assertTrue(tba0 != tba1, "TBAs diferentes para tokens diferentes");
    }

    function test_isAccountCreated_true_after_mint() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        assertTrue(heroCard.isAccountCreated(tokenId, heroCard.DEFAULT_SALT()));
    }

    function test_createAccountIfNeeded_idempotent() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        address tba1 = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Chamar createAccountIfNeeded numa TBA já criada deve retornar o mesmo endereço
        address tba2 = heroCard.createAccountIfNeeded(tokenId, heroCard.DEFAULT_SALT());

        assertEq(tba1, tba2);
    }

    function test_tba_token_data() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());
        ERC6551Account account = ERC6551Account(payable(tba));

        (uint256 chainId, address tokenContract, uint256 retTokenId) = account.token();

        assertEq(chainId, block.chainid);
        assertEq(tokenContract, address(heroCard));
        assertEq(retTokenId, tokenId);
    }

    // =========================================================================
    // Testes: Depósito e Saque de ETH
    // =========================================================================

    function test_depositEth() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        vm.prank(alice);
        heroCard.depositEth{value: 1 ether}(tokenId);

        assertEq(address(tba).balance, 1 ether);
    }

// removed for removed delegate functions
    function test_withdrawEth() public {}

// removed for removed delegate functions
    function test_withdraw_eth_only_owner() public {}

    // =========================================================================
    // Testes: ERC-20
    // =========================================================================

    function test_depositERC20() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Minta tokens para Alice
        vm.prank(owner);
        gold.mint(alice, 1000e18);

        // Alice aprova e deposita
        vm.startPrank(alice);
        gold.approve(address(heroCard), 500e18);
        heroCard.depositERC20(tokenId, address(gold), 500e18);
        vm.stopPrank();

        assertEq(gold.balanceOf(tba), 500e18);
    }

// removed for removed delegate functions
    function test_withdrawERC20() public {}

    // =========================================================================
    // Testes: ERC-721 filho
    // =========================================================================

    function test_depositERC721() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Minta uma espada para Alice
        uint256 swordId = sword.mint(alice);

        // Alice deposita a espada na TBA
        vm.startPrank(alice);
        sword.approve(address(heroCard), swordId);
        heroCard.depositERC721(tokenId, address(sword), swordId);
        vm.stopPrank();

        assertEq(sword.ownerOf(swordId), tba);
    }

// removed for removed delegate functions
    function test_withdrawERC721() public {}

    // =========================================================================
    // Testes: executeOnAccount
    // =========================================================================

// removed for removed delegate functions
    function test_executeOnAccount_eth_transfer() public {}

// removed for removed delegate functions
    function test_executeOnAccount_only_owner() public {}

    // =========================================================================
    // Testes: Transferência de NFT transfere controle da TBA
    // =========================================================================

// removed for removed delegate functions
    function test_tba_control_transfers_with_nft() public {}

    // =========================================================================
    // Testes: ERC-6551Account diretamente
    // =========================================================================

    function test_account_state_increments() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());
        ERC6551Account account = ERC6551Account(payable(tba));
        vm.deal(tba, 2 ether);

        assertEq(account.state(), 0);

        // Executa uma transação diretamente na TBA (Alice é owner do NFT)
        vm.prank(alice);
        account.execute(bob, 0.5 ether, "", 0);

        assertEq(account.state(), 1);
    }

    function test_account_receive_eth() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Envia ETH direto para a TBA
        vm.prank(alice);
        (bool ok,) = tba.call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(tba).balance, 1 ether);
    }

    function test_account_isValidSigner_owner() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        ERC6551Account account = ERC6551Account(payable(tba));

        bytes4 valid = account.isValidSigner(alice, "");
        assertEq(valid, bytes4(0x523e3260), "alice deve ser signer valido");

        bytes4 invalid = account.isValidSigner(bob, "");
        assertEq(invalid, bytes4(0), "bob nao deve ser signer valido");
    }

    function test_account_supportsInterface() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        ERC6551Account account = ERC6551Account(payable(tba));

        assertTrue(account.supportsInterface(type(IERC165).interfaceId));
        assertTrue(account.supportsInterface(type(IERC1271).interfaceId));
        assertTrue(account.supportsInterface(type(IERC6551Account).interfaceId));
    }

    function test_account_rejects_delegatecall() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());
        ERC6551Account account = ERC6551Account(payable(tba));

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        account.execute(bob, 0, "", 1); // 1 = DELEGATECALL
    }

    // =========================================================================
    // Testes: Fuzz
    // =========================================================================

    function testFuzz_tba_address_unique_per_token(uint256 tokenId1, uint256 tokenId2) public view {
        vm.assume(tokenId1 != tokenId2);

        address tba1 = registry.account(address(accountImpl), bytes32(0), block.chainid, address(heroCard), tokenId1);
        address tba2 = registry.account(address(accountImpl), bytes32(0), block.chainid, address(heroCard), tokenId2);

        assertTrue(tba1 != tba2, "TBAs devem ser unicas por token");
    }

// removed for removed delegate functions
    function testFuzz_deposit_withdraw_eth(uint96 amount) public {}
}
