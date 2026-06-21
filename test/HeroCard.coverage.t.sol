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

    function test_revokeERC20Approvals_success() public {
        vm.startPrank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        vm.stopPrank();

        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        usdc.mint(alice, 1000e6);
        vm.startPrank(alice);
        usdc.approve(address(heroCard), 1000e6);
        heroCard.depositERC20(tokenId, address(usdc), 1000e6);

        // Aprova um contrato malicioso
        address malicious = makeAddr("malicious");
        heroCard.executeOnAccount(
            tokenId, address(usdc), 0, abi.encodeWithSelector(IERC20.approve.selector, malicious, 500e6)
        );

        assertEq(usdc.allowance(tba, malicious), 500e6);

        address[] memory tokens = new address[](1);
        tokens[0] = address(usdc);
        address[] memory spenders = new address[](1);
        spenders[0] = malicious;

        heroCard.revokeERC20Approvals(tokenId, tokens, spenders);

        assertEq(usdc.allowance(tba, malicious), 0);
        vm.stopPrank();
    }

    function test_revokeERC20Approvals_reverts_different_length() public {
        vm.startPrank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        address[] memory spenders = new address[](2);

        vm.prank(alice);
        vm.expectRevert("HeroCard: arrays de tamanho diferente");
        heroCard.revokeERC20Approvals(tokenId, tokens, spenders);
    }

    function test_revokeERC721Operators_success() public {
        vm.startPrank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        vm.stopPrank();

        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        uint256 mockNftId = nft.mint(alice);
        vm.startPrank(alice);
        nft.approve(address(heroCard), mockNftId);
        heroCard.depositERC721(tokenId, address(nft), mockNftId);

        address malicious = makeAddr("malicious");
        heroCard.executeOnAccount(
            tokenId, address(nft), 0, abi.encodeWithSelector(IERC721.setApprovalForAll.selector, malicious, true)
        );

        assertTrue(nft.isApprovedForAll(tba, malicious));

        address[] memory tokens = new address[](1);
        tokens[0] = address(nft);
        address[] memory operators = new address[](1);
        operators[0] = malicious;

        heroCard.revokeERC721Operators(tokenId, tokens, operators);

        assertFalse(nft.isApprovedForAll(tba, malicious));
        vm.stopPrank();
    }

    function test_revokeERC721Operators_reverts_different_length() public {
        vm.startPrank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        vm.stopPrank();

        address[] memory tokens = new address[](1);
        address[] memory operators = new address[](0);

        vm.prank(alice);
        vm.expectRevert("HeroCard: arrays de tamanho diferente");
        heroCard.revokeERC721Operators(tokenId, tokens, operators);
    }
}
