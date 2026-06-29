// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCardSBT.sol";

contract HeroCardSBTTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCardSBT public sbt;

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new HeroCardAccount();
        sbt = new HeroCardSBT(address(registry), address(accountImpl));
        sbt.grantRole(sbt.MINTER_ROLE(), minter);
        vm.stopPrank();

        vm.deal(alice, 10 ether);
    }

    function test_sbt_mint() public {
        vm.prank(minter);
        uint256 tokenId = sbt.mint(alice, "");

        assertEq(sbt.ownerOf(tokenId), alice);
        assertEq(sbt.totalSupply(), 1);
    }

    function test_sbt_uri() public {
        vm.prank(minter);
        uint256 tokenId = sbt.mint(alice, "ipfs://custom_uri");
        // tokenURI will return whatever was passed during minting, and the baseURI handles the rest if empty
        assertEq(sbt.tokenURI(tokenId), "ipfs://custom_uri");
    }

    function test_sbt_batch_mint_uri() public {
        vm.prank(minter);
        uint256 firstId = sbt.mintBatch(alice, 2);

        assertEq(sbt.ownerOf(firstId), alice);
        assertEq(sbt.tokenURI(firstId), "ipfs://QmHeroCardSBT0");
        assertEq(sbt.tokenURI(firstId + 1), "ipfs://QmHeroCardSBT1");
    }

    function test_sbt_transfer_reverts() public {
        vm.prank(minter);
        uint256 tokenId = sbt.mint(alice, "");

        vm.prank(alice);
        vm.expectRevert("HeroCardSBT: Transferencia nao permitida (Soulbound)");
        sbt.transferFrom(alice, bob, tokenId);

        vm.prank(alice);
        vm.expectRevert("HeroCardSBT: Transferencia nao permitida (Soulbound)");
        sbt.safeTransferFrom(alice, bob, tokenId);

        // Ensure Alice is still the owner
        assertEq(sbt.ownerOf(tokenId), alice);
    }

// removed for removed delegate functions
    function test_sbt_tba_functionality() public {}
}
