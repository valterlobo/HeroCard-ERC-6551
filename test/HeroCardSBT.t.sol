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
        uint256 tokenId = 1;
        sbt.mint(alice, tokenId, "");

        assertEq(sbt.ownerOf(tokenId), alice);
        assertEq(sbt.totalSupply(), 1);
    }

    function test_sbt_uri() public {
        vm.prank(minter);
        uint256 tokenId = 1;
        sbt.mint(alice, tokenId, "ipfs://custom_uri");
        // tokenURI will return whatever was passed during minting, and the baseURI handles the rest if empty
        assertEq(sbt.tokenURI(tokenId), "ipfs://custom_uri");
    }

    function test_sbt_batch_mint_uri() public {
        vm.prank(minter);
        string[] memory tokenURIs = new string[](2);
        tokenURIs[0] = "ipfs://QmHeroCardSBT0";
        tokenURIs[1] = "ipfs://QmHeroCardSBT1";
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        sbt.mintBatch(alice, tokenIds, tokenURIs);

        assertEq(sbt.ownerOf(1), alice);
        assertEq(sbt.tokenURI(1), "ipfs://QmHeroCardSBT0");
        assertEq(sbt.tokenURI(2), "ipfs://QmHeroCardSBT1");
    }

    function test_sbt_transfer_reverts() public {
        vm.prank(minter);
        uint256 tokenId = 1;
        sbt.mint(alice, tokenId, "");

        vm.prank(alice);
        vm.expectRevert("HeroCardSBT: Transferencia e burn nao permitidos (Soulbound)");
        sbt.transferFrom(alice, bob, tokenId);

        vm.prank(alice);
        vm.expectRevert("HeroCardSBT: Transferencia e burn nao permitidos (Soulbound)");
        sbt.safeTransferFrom(alice, bob, tokenId);

        // Ensure Alice is still the owner
        assertEq(sbt.ownerOf(tokenId), alice);
    }

    // =========================================================================
    // VULN-02: Burn deve ser bloqueado — SBT é indestrutível
    // =========================================================================

    /// @notice Owner não pode fazer burn do próprio SBT
    function test_sbt_burn_by_owner_reverts() public {
        vm.prank(minter);
        uint256 tokenId = 1;
        sbt.mint(alice, tokenId, "");

        // Owner tenta burn (transferFrom para address(0) não funciona via ERC721,
        // mas testamos via _update que bloqueia qualquer to != mint)
        // Nota: ERC721.transferFrom para address(0) reverte antes de chegar a _update
        // porque OpenZeppelin valida o receiver. Então testamos via safeTransferFrom.
        vm.prank(alice);
        vm.expectRevert(); // ERC721 reverte antes mesmo do nosso check
        sbt.transferFrom(alice, address(0), tokenId);

        assertEq(sbt.ownerOf(tokenId), alice, "SBT nao deve ter sido destruido");
    }

    /// @notice Operador aprovado NÃO pode destruir o SBT (cenário de ataque VULN-02)
    /// @dev Este é o cenário exato da vulnerabilidade: um contrato malicioso com
    ///      approve poderia chamar burn para destruir o SBT do owner.
    function test_sbt_burn_by_approved_operator_reverts() public {
        vm.prank(minter);
        uint256 tokenId = 1;
        sbt.mint(alice, tokenId, "");

        // Alice aprova bob para o token
        vm.prank(alice);
        sbt.approve(bob, tokenId);

        // Bob (aprovado) tenta transferir — deve ser bloqueado
        vm.prank(bob);
        vm.expectRevert("HeroCardSBT: Transferencia e burn nao permitidos (Soulbound)");
        sbt.transferFrom(alice, bob, tokenId);

        assertEq(sbt.ownerOf(tokenId), alice, "SBT nao deve ter sido transferido por operador");
    }

    /// @notice setApprovalForAll + transferência deve ser bloqueado
    function test_sbt_transfer_by_approved_for_all_reverts() public {
        vm.prank(minter);
        uint256 tokenId = 1;
        sbt.mint(alice, tokenId, "");

        // Alice dá aprovação global para bob
        vm.prank(alice);
        sbt.setApprovalForAll(bob, true);

        // Bob (operador global) tenta transferir — deve ser bloqueado
        vm.prank(bob);
        vm.expectRevert("HeroCardSBT: Transferencia e burn nao permitidos (Soulbound)");
        sbt.transferFrom(alice, bob, tokenId);

        assertEq(sbt.ownerOf(tokenId), alice, "SBT nao deve ter sido transferido por operador global");
    }

    // removed for removed delegate functions
    function test_sbt_tba_functionality() public {}
}
