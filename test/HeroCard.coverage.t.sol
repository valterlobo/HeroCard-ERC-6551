// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/HeroCard.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";

contract HeroCardCoverageTest is Test {
    HeroCard public heroCard;
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    MockERC20 public usdc;
    MockERC721 public nft;

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new HeroCardAccount();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        heroCard.grantRole(heroCard.PAUSER_ROLE(), deployer);

        usdc = new MockERC20("USD Coin", "USDC");
        nft = new MockERC721("Mock NFT", "MNFT");
        vm.stopPrank();

        vm.deal(alice, 10 ether);
    }

    function test_unpause() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        heroCard.pause();
        assertTrue(heroCard.paused());
        heroCard.unpause();
        assertFalse(heroCard.paused());
        vm.stopPrank();
    }

    // removed for removed delegate functions
    function test_revokeERC20Approvals_success() public {}

    // removed for removed delegate functions
    function test_revokeERC20Approvals_reverts_different_length() public {}

    // removed for removed delegate functions
    function test_revokeERC721Operators_success() public {}

    // removed for removed delegate functions
    function test_revokeERC721Operators_reverts_different_length() public {}
}
