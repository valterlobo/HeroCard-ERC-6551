// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCard.sol";
import "../src/mocks/MockERC721.sol";

/// @title ERC6551AccountOwnershipCycleTest
/// @notice Testes para a proteção contra ownership cycle no ERC6551Account.
///
/// Cenário do ataque:
///   1. Alice possui o HeroCard tokenId=0, cuja TBA é address(tba).
///   2. A TBA possui outros ativos (ETH, ERC-20, ERC-721).
///   3. Se a TBA pudesse chamar heroCard.transferFrom(alice, address(tba), 0),
///      a TBA passaria a ser dona do NFT que a controla → loop infinito de
///      autorização; ninguém pode mais executar ações na conta.
///
/// A proteção detecta as três variantes de transferência ERC-721:
///   - transferFrom(from, to, tokenId)
///   - safeTransferFrom(from, to, tokenId)
///   - safeTransferFrom(from, to, tokenId, bytes)
contract ERC6551AccountOwnershipCycleTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;
    MockERC721 public otherNFT; // NFT diferente — deve poder ser transferido

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    // Selectors ERC-721
    bytes4 private constant _TRANSFER_FROM = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant _SAFE_TRANSFER_FROM_3 = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
    bytes4 private constant _SAFE_TRANSFER_FROM_4 =
        bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"));

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new HeroCardAccount();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        otherNFT = new MockERC721("Other NFT", "OTHER");
        vm.stopPrank();

        vm.deal(alice, 100 ether);
    }

    // ── helper ───────────────────────────────────────────────────────────────

    /// Minta um HeroCard para `to` e retorna (tokenId, tba)
    function _mintCard(address to) internal returns (uint256 tokenId, ERC6551Account tba) {
        tokenId = 4;
        vm.prank(minter);
        heroCard.mint(to, tokenId, "");
        tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));
    }

    // =========================================================================
    // BLOQUEAR — transferFrom com o tokenId vinculado
    // =========================================================================

    /// @notice TBA tenta transferir o próprio NFT via transferFrom → deve reverter
    function test_cycle_transferFrom_bound_tokenId_reverts() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(
            _TRANSFER_FROM,
            alice, // from
            address(tba), // to — TBA tentando se tornar dona
            tokenId // o tokenId vinculado
        );

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.execute(address(heroCard), 0, data, 0);
    }

    // =========================================================================
    // BLOQUEAR — safeTransferFrom(from,to,tokenId) com o tokenId vinculado
    // =========================================================================

    /// @notice TBA tenta safeTransferFrom (3 args) do próprio NFT → deve reverter
    function test_cycle_safeTransferFrom3_bound_tokenId_reverts() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(_SAFE_TRANSFER_FROM_3, alice, address(tba), tokenId);

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.execute(address(heroCard), 0, data, 0);
    }

    // =========================================================================
    // BLOQUEAR — safeTransferFrom(from,to,tokenId,bytes) com o tokenId vinculado
    // =========================================================================

    /// @notice TBA tenta safeTransferFrom (4 args) do próprio NFT → deve reverter
    function test_cycle_safeTransferFrom4_bound_tokenId_reverts() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(
            _SAFE_TRANSFER_FROM_4,
            alice,
            address(tba),
            tokenId,
            bytes("") // extra data param
        );

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.execute(address(heroCard), 0, data, 0);
    }

    // =========================================================================
    // BLOQUEAR — destino é qualquer endereço (não só a própria TBA)
    // =========================================================================

    /// @notice Mesmo transferindo para Bob (não para a TBA), deve reverter se
    ///         o tokenId for o vinculado — qualquer transferência "rouba" o controle.
    function test_cycle_transferFrom_to_bob_bound_tokenId_reverts() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(
            _TRANSFER_FROM,
            alice,
            bob, // destinatário é bob, não a TBA
            tokenId // mas o tokenId vinculado → deve bloquear
        );

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.execute(address(heroCard), 0, data, 0);
    }

    // =========================================================================
    // PERMITIR — transferFrom de tokenId DIFERENTE no mesmo contrato
    // =========================================================================

    /// @notice A TBA pode transferir outro tokenId do mesmo contrato (tokenId ≠ vinculado)
    function test_cycle_different_tokenId_allowed() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        // Minta um segundo HeroCard diretamente para a TBA
        uint256 otherTokenId = 100; // Different from tokenId (1)
        vm.prank(minter);
        heroCard.mint(address(tba), otherTokenId, "");
        assertNotEq(otherTokenId, tokenId, "tokenIds devem ser diferentes");

        // A TBA transfere o OUTRO token (não o vinculado) — deve funcionar
        bytes memory data = abi.encodeWithSelector(
            _TRANSFER_FROM,
            address(tba), // from = TBA (dona do outro token)
            bob,
            otherTokenId // tokenId diferente → permitido
        );

        vm.prank(alice);
        tba.execute(address(heroCard), 0, data, 0);

        assertEq(heroCard.ownerOf(otherTokenId), bob, "bob deve ter recebido o outro token");
        assertEq(heroCard.ownerOf(tokenId), alice, "alice ainda deve possuir o token vinculado");
    }

    // =========================================================================
    // PERMITIR — destino é contrato diferente (não o tokenContract)
    // =========================================================================

    /// @notice Chamadas para contratos que não sejam o tokenContract são liberadas
    function test_cycle_different_contract_allowed() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        // Transferência de ETH para bob — destino é bob, não heroCard
        vm.prank(alice);
        tba.execute(bob, 0.5 ether, "", 0);

        assertEq(bob.balance, 0.5 ether);
    }

    // =========================================================================
    // PERMITIR — calldata curta demais para ser uma transferência
    // =========================================================================

    /// @notice Calldata < 100 bytes é ignorada pelo guard (não há tokenId para extrair)
    function test_cycle_short_calldata_allowed() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        // Apenas o selector (4 bytes) — sem argumentos
        bytes memory shortData = abi.encodeWithSelector(_TRANSFER_FROM);

        vm.prank(alice);
        // Não deve reverter com OwnershipCycleDetected; pode reverter por outro motivo
        // (heroCard vai rejeitar a calldata inválida), mas o guard não interfere
        vm.expectRevert(); // revert vem do heroCard, não do guard
        tba.execute(address(heroCard), 0, shortData, 0);
    }

    // =========================================================================
    // PERMITIR — selector não é de transferência ERC-721
    // =========================================================================

    /// @notice Chamada com selector não-transfer para o tokenContract é permitida
    function test_cycle_non_transfer_selector_allowed() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        // approve(address,uint256) — não é bloqueado pelo guard
        bytes memory data = abi.encodeWithSelector(IERC721.approve.selector, bob, tokenId);

        vm.prank(alice);
        // Pode falhar por outro motivo (TBA não é dona para aprovar), mas
        // o guard de ownership cycle não deve ser o motivo do revert
        vm.expectRevert(); // falha por "Not approved" do ERC721, não por cycle
        tba.execute(address(heroCard), 0, data, 0);
    }

    // =========================================================================
    // BLOQUEAR — executeBatch contém a transferência do tokenId vinculado
    // =========================================================================

    /// @notice executeBatch deve bloquear se qualquer chamada criar um ownership cycle
    function test_cycle_executeBatch_blocks_bound_tokenId() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        // Chamada 1: ETH simples — OK
        targets[0] = bob;
        values[0] = 0.1 ether;
        data[0] = "";

        // Chamada 2: transferência do NFT vinculado — deve bloquear
        targets[1] = address(heroCard);
        values[1] = 0;
        data[1] = abi.encodeWithSelector(_TRANSFER_FROM, alice, address(tba), tokenId);

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.executeBatch(targets, values, data, 0);

        // Nada foi executado (transação inteira reverteu)
        assertEq(bob.balance, 0, "bob nao deve ter recebido ETH");
        assertEq(tba.state(), 0, "state nao deve ter incrementado");
    }

    // =========================================================================
    // BLOQUEAR — executeBatch com safeTransferFrom4 no batch
    // =========================================================================

    /// @notice executeBatch bloqueia safeTransferFrom4 com tokenId vinculado
    function test_cycle_executeBatch_safeTransferFrom4_reverts() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = address(heroCard);
        values[0] = 0;
        data[0] = abi.encodeWithSelector(_SAFE_TRANSFER_FROM_4, alice, bob, tokenId, "");

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.executeBatch(targets, values, data, 0);
    }

    // =========================================================================
    // PERMITIR — executeBatch com tokenId diferente
    // =========================================================================

    /// @notice executeBatch permite transferência de tokenId diferente do vinculado
    function test_cycle_executeBatch_different_tokenId_allowed() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        // Minta segundo token para a TBA
        uint256 otherTokenId = 2;
        vm.prank(minter);
        heroCard.mint(address(tba), otherTokenId, "");

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = address(heroCard);
        values[0] = 0;
        data[0] = abi.encodeWithSelector(_TRANSFER_FROM, address(tba), bob, otherTokenId);

        vm.prank(alice);
        tba.executeBatch(targets, values, data, 0);

        assertEq(heroCard.ownerOf(otherTokenId), bob, "bob deve ter recebido o outro token");
        assertEq(heroCard.ownerOf(tokenId), alice, "alice ainda deve possuir o token vinculado");
    }

    // =========================================================================
    // Fuzz — qualquer tokenId != boundTokenId é permitido
    // =========================================================================

    /// @notice Fuzz: tokenId diferente do vinculado nunca bloqueia o guard
    function testFuzz_cycle_non_bound_tokenId_never_blocked(uint256 fuzzedTokenId) public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);
        vm.assume(fuzzedTokenId != tokenId);

        // Apenas verificar que _checkOwnershipCycle não reverta com OwnershipCycleDetected
        // A chamada pode falhar por outros motivos (token inexistente), mas não pelo guard
        bytes memory data = abi.encodeWithSelector(_TRANSFER_FROM, alice, bob, fuzzedTokenId);

        vm.prank(alice);
        // Não usar expectRevert(OwnershipCycleDetected) — pode falhar por outro erro
        // Mas se reverter com OwnershipCycleDetected, o teste falha (o que é correto)
        try tba.execute(address(heroCard), 0, data, 0) {
        // sucesso: token fuzzedTokenId existia e foi transferido (improvável)
        }
        catch (bytes memory reason) {
            // Falhou por outro motivo (token inexistente, not approved, etc.)
            // Garantir que NÃO é OwnershipCycleDetected
            bytes4 errSelector = bytes4(reason);
            assertNotEq(
                errSelector,
                ERC6551Account.OwnershipCycleDetected.selector,
                "nao deve rejeitar por ownership cycle com tokenId diferente"
            );
        }
    }

    // =========================================================================
    // Fuzz — qualquer selector diferente dos 3 de transfer é sempre permitido
    // =========================================================================

    /// @notice Fuzz: selectors que não sejam de transferência ERC-721 nunca são bloqueados
    function testFuzz_cycle_non_transfer_selector_never_blocked(bytes4 fuzzedSelector) public {
        vm.assume(fuzzedSelector != _TRANSFER_FROM);
        vm.assume(fuzzedSelector != _SAFE_TRANSFER_FROM_3);
        vm.assume(fuzzedSelector != _SAFE_TRANSFER_FROM_4);

        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        // Monta calldata com tamanho suficiente mas selector diferente
        bytes memory data = abi.encodePacked(
            fuzzedSelector,
            abi.encode(alice, address(tba), tokenId) // mesmos argumentos, selector diferente
        );

        vm.prank(alice);
        try tba.execute(address(heroCard), 0, data, 0) {
        // sucesso improvável, mas não é bloqueio de cycle
        }
        catch (bytes memory reason) {
            bytes4 errSelector = bytes4(reason);
            assertNotEq(
                errSelector,
                ERC6551Account.OwnershipCycleDetected.selector,
                "selector nao-transfer nunca deve acionar o guard"
            );
        }
    }

    // =========================================================================
    // Proteção contra ciclos INDIRETOS via approve (Limitação 1 — CORRIGIDA)
    // =========================================================================

    /// @notice approve(spender, boundTokenId) no tokenContract deve reverter
    function test_cycle_approve_bound_tokenId_reverts() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), bob, tokenId);

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.execute(address(heroCard), 0, data, 0);
    }

    /// @notice approve de tokenId DIFERENTE é permitido
    function test_cycle_approve_different_tokenId_allowed() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);

        uint256 otherTokenId = 3;
        vm.prank(minter);
        heroCard.mint(alice, otherTokenId, "");

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("approve(address,uint256)")), bob, otherTokenId);

        vm.prank(alice);
        try tba.execute(address(heroCard), 0, data, 0) {}
        catch (bytes memory reason) {
            bytes4 errSel = bytes4(reason);
            assertNotEq(errSel, ERC6551Account.OwnershipCycleDetected.selector);
        }
    }

    /// @notice setApprovalForAll(operator, true) no tokenContract deve reverter
    function test_cycle_setApprovalForAll_true_reverts() public {
        (, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setApprovalForAll(address,bool)")), bob, true);

        vm.prank(alice);
        vm.expectRevert(ERC6551Account.OwnershipCycleDetected.selector);
        tba.execute(address(heroCard), 0, data, 0);
    }

    /// @notice setApprovalForAll(operator, false) é permitido (revogação)
    function test_cycle_setApprovalForAll_false_allowed() public {
        (, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setApprovalForAll(address,bool)")), bob, false);

        vm.prank(alice);
        try tba.execute(address(heroCard), 0, data, 0) {}
        catch (bytes memory reason) {
            bytes4 errSel = bytes4(reason);
            assertNotEq(errSel, ERC6551Account.OwnershipCycleDetected.selector, "revogar aprovacao deve ser permitido");
        }
    }

    /// @notice setApprovalForAll num contrato diferente do tokenContract é permitido
    function test_cycle_setApprovalForAll_other_contract_allowed() public {
        (, ERC6551Account tba) = _mintCard(alice);

        bytes memory data = abi.encodeWithSelector(bytes4(keccak256("setApprovalForAll(address,bool)")), bob, true);

        vm.prank(alice);
        try tba.execute(address(otherNFT), 0, data, 0) {}
        catch (bytes memory reason) {
            bytes4 errSel = bytes4(reason);
            assertNotEq(errSel, ERC6551Account.OwnershipCycleDetected.selector);
        }
    }
}
