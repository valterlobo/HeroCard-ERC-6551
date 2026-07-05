// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCard.sol";

/// @title ERC6551AccountBranchesTest
/// @notice Cobertura de branches restantes do ERC6551Account:
///         1. executeBatch() — todos os require e caminho feliz
///         2. _owner()       — branch chainId != block.chainid (return address(0))
contract ERC6551AccountBranchesTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public carol = makeAddr("carol");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new HeroCardAccount();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
    }

    // ── helper ───────────────────────────────────────────────────────────────

    function _mintCard(address to) internal returns (uint256 tokenId, ERC6551Account tba) {
        tokenId = 1;
        vm.prank(minter);
        heroCard.mint(to, tokenId, "");
        tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));
    }

    // =========================================================================
    // _owner() — branch: chainId != block.chainid → retorna address(0)
    // BRDA:293,9,0,0 — 0 hits antes deste teste
    // =========================================================================

    /// @notice Quando o chainId embutido no bytecode ≠ block.chainid, _owner() deve
    ///         retornar address(0), tornando qualquer signer inválido.
    function test_owner_returns_zero_on_wrong_chain() public {
        (, ERC6551Account tba) = _mintCard(alice);

        // Na chain atual (31337 por padrão do Foundry), alice é signer válido
        bytes4 validResult = tba.isValidSigner(alice, "");
        assertEq(validResult, bytes4(0x523e3260), "alice deve ser signer valido na chain correta");

        // Simula execução em outra chain — _owner() retornará address(0)
        vm.chainId(999_999);

        // isValidSigner(alice) deve retornar 0 porque _owner() == address(0)
        bytes4 invalidResult = tba.isValidSigner(alice, "");
        assertEq(invalidResult, bytes4(0), "nenhum signer deve ser valido em chain errada");

        // execute() também deve reverter (nao autorizado) na chain errada
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(bob, 0.1 ether, "", 0);
    }

    /// @notice isValidSignature() deve retornar inválido quando chainId difere
    function test_isValidSignature_wrong_chain_returns_invalid() public {
        uint256 privKey = 0xA11CE;
        address signer = vm.addr(privKey);

        vm.prank(minter);
        uint256 tokenId = 2;
        heroCard.mint(signer, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        bytes32 hash = keccak256("mensagem");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Válida na chain correta
        assertEq(tba.isValidSignature(hash, sig), bytes4(0x1626ba7e), "deve ser valida na chain correta");

        // Muda para chain diferente → _owner() == address(0) → inválida
        vm.chainId(1337);
        assertEq(tba.isValidSignature(hash, sig), bytes4(0xffffffff), "deve ser invalida em chain errada");
    }

    // =========================================================================
    // executeBatch() — branch: caller não autorizado
    // BRDA:214,4,0 — require(_isValidSigner) falso
    // =========================================================================

    /// @notice Bob (não-owner) chama executeBatch() → deve reverter "nao autorizado"
    function test_executeBatch_unauthorized_reverts() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = bob;
        values[0] = 0.1 ether;
        data[0] = "";

        vm.prank(bob);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.executeBatch(targets, values, data, 0);
    }

    // =========================================================================
    // executeBatch() — branch: operation != 0
    // BRDA:215,5,0 — require(operation == OP_CALL) falso
    // =========================================================================

    /// @notice operation != 0 → deve reverter "operacao nao suportada"
    function test_executeBatch_invalid_operation_reverts() public {
        (, ERC6551Account tba) = _mintCard(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = bob;
        values[0] = 0;
        data[0] = "";

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.executeBatch(targets, values, data, 1);

        // operation = 2 (CREATE)
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.executeBatch(targets, values, data, 2);
    }

    // =========================================================================
    // executeBatch() — branch: array vazio
    // BRDA:218,6,0 — require(length > 0) falso
    // =========================================================================

    /// @notice Array vazio → deve reverter "batch vazio"
    function test_executeBatch_empty_batch_reverts() public {
        (, ERC6551Account tba) = _mintCard(alice);

        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory data = new bytes[](0);

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: batch vazio");
        tba.executeBatch(targets, values, data, 0);
    }

    // =========================================================================
    // executeBatch() — branch: arrays com tamanhos diferentes
    // BRDA:219,7,0 — require(values.length == length && data.length == length) falso
    // =========================================================================

    /// @notice values.length != targets.length → deve reverter "arrays com tamanhos diferentes"
    function test_executeBatch_mismatched_values_reverts() public {
        (, ERC6551Account tba) = _mintCard(alice);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](1); // tamanho errado
        bytes[] memory data = new bytes[](2);
        targets[0] = bob;
        targets[1] = carol;
        values[0] = 0;
        data[0] = "";
        data[1] = "";

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: arrays com tamanhos diferentes");
        tba.executeBatch(targets, values, data, 0);
    }

    /// @notice data.length != targets.length → deve reverter "arrays com tamanhos diferentes"
    function test_executeBatch_mismatched_data_reverts() public {
        (, ERC6551Account tba) = _mintCard(alice);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](1); // tamanho errado
        targets[0] = bob;
        targets[1] = carol;
        values[0] = 0;
        values[1] = 0;
        data[0] = "";

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: arrays com tamanhos diferentes");
        tba.executeBatch(targets, values, data, 0);
    }

    // =========================================================================
    // executeBatch() — caminho feliz: executa múltiplas chamadas
    // BRDA:219,7,1 / BRDA:218,6,1 / BRDA:215,5,1 / BRDA:214,4,1 / BRDA:232,8,0 (success)
    // =========================================================================

    /// @notice Batch com 3 transferências ETH → todas devem ser executadas
    function test_executeBatch_success_multiple_calls() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 10 ether);

        uint256 bobBefore = bob.balance;
        uint256 carolBefore = carol.balance;
        uint256 stateBefore = tba.state();

        address[] memory targets = new address[](3);
        uint256[] memory values = new uint256[](3);
        bytes[] memory data = new bytes[](3);

        targets[0] = bob;
        targets[1] = carol;
        targets[2] = bob;
        values[0] = 1 ether;
        values[1] = 0.5 ether;
        values[2] = 0.25 ether;
        data[0] = "";
        data[1] = "";
        data[2] = "";

        vm.prank(alice);
        bytes[] memory results = tba.executeBatch(targets, values, data, 0);

        // Resultados: transferências ETH retornam bytes vazios
        assertEq(results.length, 3, "deve retornar 3 resultados");

        // State incrementou exatamente 1 (não por chamada, mas por executeBatch)
        assertEq(tba.state(), stateBefore + 1, "state deve ter incrementado 1");

        // Saldos corretos
        assertEq(bob.balance, bobBefore + 1.25 ether, "bob deve ter recebido 1.25 ether");
        assertEq(carol.balance, carolBefore + 0.5 ether, "carol deve ter recebido 0.5 ether");
    }

    /// @notice Batch com 1 chamada → caminho mínimo válido
    function test_executeBatch_single_call_success() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = bob;
        values[0] = 0.5 ether;
        data[0] = "";

        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        bytes[] memory results = tba.executeBatch(targets, values, data, 0);

        assertEq(results.length, 1, "deve retornar 1 resultado");
        assertEq(tba.state(), 1, "state deve ser 1");
        assertEq(bob.balance, bobBefore + 0.5 ether, "bob deve ter recebido 0.5 ether");
    }

    // =========================================================================
    // executeBatch() — branch: chamada interna falha (success == false)
    // BRDA:232,8,0 — if (!success) true
    // =========================================================================

    /// @notice Quando uma chamada do batch falha, toda a transação reverte
    function test_executeBatch_inner_call_fails_reverts() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        // Deploy contrato que sempre reverte
        BatchReverter reverter = new BatchReverter();

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        // Primeira chamada: OK (transferência simples para bob)
        targets[0] = bob;
        values[0] = 0.1 ether;
        data[0] = "";

        // Segunda chamada: sempre reverte
        targets[1] = address(reverter);
        values[1] = 0;
        data[1] = abi.encodeWithSelector(BatchReverter.alwaysFails.selector);

        uint256 stateBefore = tba.state();
        uint256 bobBefore = bob.balance;

        vm.prank(alice);
        vm.expectRevert("BatchReverter: falha intencional");
        tba.executeBatch(targets, values, data, 0);

        // Toda a transação reverteu: state e saldo não mudaram
        assertEq(tba.state(), stateBefore, "state nao deve ter mudado");
        assertEq(bob.balance, bobBefore, "bob nao deve ter recebido ETH");
    }

    // =========================================================================
    // executeBatch() — evento BatchExecuted emitido
    // =========================================================================

    /// @notice executeBatch() deve emitir BatchExecuted com count correto
    function test_executeBatch_emits_BatchExecuted() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);
        targets[0] = bob;
        targets[1] = carol;
        values[0] = 0.1 ether;
        values[1] = 0.1 ether;
        data[0] = "";
        data[1] = "";

        vm.prank(alice);
        vm.expectEmit(false, false, false, true);
        emit ERC6551Account.BatchExecuted(2, 0);
        tba.executeBatch(targets, values, data, 0);
    }

    // =========================================================================
    // executeBatch() — tokenContract (HeroCard) pode chamar como signer
    // =========================================================================

    /// @notice heroCard (tokenContract) pode chamar executeBatch() via _isValidSigner
    function test_executeBatch_via_tokenContract_signer() public {
        // removed because the check was removed
    }

    // =========================================================================
    // executeBatch() — prevenção de drenagem de ETH (CRÍTICO)
    // =========================================================================

    /// @notice Garante que executeBatch não drena ETH custodiado além do permitido
    /// @dev Cenário do relatório de auditoria: TBA tem 10 ETH acumulados.
    ///      Atacante tenta enviar 15 + 15 ETH via batch com msg.value=0.
    ///      Deve reverter com "saldo ETH insuficiente".
    function test_executeBatch_cannot_drain_eth_beyond_balance() public {
        (, ERC6551Account tba) = _mintCard(alice);

        // Financia a TBA com 10 ETH custodiados
        vm.deal(address(tba), 10 ether);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = bob;
        values[0] = 15 ether; // > saldo total
        data[0] = "";

        targets[1] = bob;
        values[1] = 15 ether;
        data[1] = "";

        // Atacante (owner) tenta drenar: valores somam 30 ETH > saldo 10 ETH
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: saldo ETH insuficiente");
        tba.executeBatch(targets, values, data, 0);
    }

    /// @notice Garante que executeBatch permite usar exatamente todo o saldo disponível
    function test_executeBatch_allows_full_balance_usage() public {
        (, ERC6551Account tba) = _mintCard(alice);

        vm.deal(address(tba), 3 ether);

        address[] memory targets = new address[](2);
        uint256[] memory values = new uint256[](2);
        bytes[] memory data = new bytes[](2);

        targets[0] = bob;
        values[0] = 2 ether;
        data[0] = "";

        targets[1] = bob;
        values[1] = 1 ether; // total = 3 ether == saldo exato
        data[1] = "";

        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        tba.executeBatch(targets, values, data, 0);

        assertEq(bob.balance, bobBefore + 3 ether);
        assertEq(address(tba).balance, 0);
    }

    /// @notice Fuzz: valores que somam além do saldo sempre devem reverter
    function testFuzz_executeBatch_eth_drain_reverts(uint96 balance, uint96 extra) public {
        vm.assume(extra > 0);
        vm.assume(uint256(balance) + extra <= type(uint96).max); // evita overflow no teste

        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), balance);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = bob;
        values[0] = uint256(balance) + extra; // sempre > saldo
        data[0] = "";

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: saldo ETH insuficiente");
        tba.executeBatch(targets, values, data, 0);
    }

    // =========================================================================
    // executeBatch() — fuzz: qualquer operation != 0 rejeitada
    // =========================================================================

    /// @notice Fuzz: qualquer operation != 0 em executeBatch deve reverter
    function testFuzz_executeBatch_invalid_operation(uint256 operation) public {
        vm.assume(operation != 0);

        (, ERC6551Account tba) = _mintCard(alice);

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory data = new bytes[](1);
        targets[0] = bob;
        values[0] = 0;
        data[0] = "";

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.executeBatch(targets, values, data, operation);
    }
}

// =============================================================================
// Mock Contracts
// =============================================================================

/// @notice Contrato que sempre reverte — usado para testar o branch !success do batch
contract BatchReverter {
    function alwaysFails() external pure {
        revert("BatchReverter: falha intencional");
    }
}
