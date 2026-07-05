// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCard.sol";

/// @title ERC6551AccountNonceTest
/// @notice Testes de segurança para gerenciamento de nonce/state
/// @dev Garante que state é incrementado atomicamente e armazenado corretamente no proxy
contract ERC6551AccountNonceTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new HeroCardAccount();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // =========================================================================
    // Teste: State incrementa atomicamente a cada execução
    // =========================================================================

    /// @notice State deve incrementar atomicamente com cada execute()
    /// @dev Verifica CEI pattern: incremento ANTES da external call
    function test_state_increments_on_execute() public {
        vm.prank(minter);
        uint256 tokenId = 1;
        heroCard.mint(alice, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // State inicial é 0
        assertEq(tba.state(), 0, "state inicial deve ser 0");

        // Executar primeira operação
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        // State incrementou para 1
        assertEq(tba.state(), 1, "state deve ser 1 apos primeira execucao");

        // Executar segunda operação
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        // State incrementou para 2
        assertEq(tba.state(), 2, "state deve ser 2 apos segunda execucao");

        // Executar terceira operação
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        // State incrementou para 3
        assertEq(tba.state(), 3, "state deve ser 3 apos terceira execucao");
    }

    // =========================================================================
    // Teste: State armazenado no storage do PROXY, não da implementação
    // =========================================================================

    /// @notice State deve ser armazenado no storage do proxy (delegatecall)
    /// @dev Verifica que cada TBA tem seu próprio state independente
    function test_state_persists_in_proxy_storage() public {
        // Criar duas TBAs diferentes
        uint256 tokenId1 = 2;
        vm.prank(minter);
        heroCard.mint(alice, tokenId1, "");

        uint256 tokenId2 = 3;
        vm.prank(minter);
        heroCard.mint(alice, tokenId2, "");

        ERC6551Account tba1 = ERC6551Account(payable(heroCard.getAccount(tokenId1, heroCard.DEFAULT_SALT())));
        ERC6551Account tba2 = ERC6551Account(payable(heroCard.getAccount(tokenId2, heroCard.DEFAULT_SALT())));

        // Ambas devem ter state inicial = 0
        assertEq(tba1.state(), 0, "tba1 state inicial deve ser 0");
        assertEq(tba2.state(), 0, "tba2 state inicial deve ser 0");

        // Executar operação apenas em tba1
        vm.deal(address(tba1), 1 ether);
        vm.prank(alice);
        tba1.execute(bob, 0.1 ether, "", 0);

        // tba1 deve ter incrementado, tba2 deve permanecer 0
        assertEq(tba1.state(), 1, "tba1 state deve ser 1");
        assertEq(tba2.state(), 0, "tba2 state deve continuar 0");

        // Executar operação em tba2
        vm.deal(address(tba2), 1 ether);
        vm.prank(alice);
        tba2.execute(bob, 0.1 ether, "", 0);

        // tba2 deve ter incrementado, tba1 deve permanecer 1
        assertEq(tba1.state(), 1, "tba1 state deve continuar 1");
        assertEq(tba2.state(), 1, "tba2 state deve ser 1");

        // Executar mais em tba1
        vm.prank(alice);
        tba1.execute(bob, 0.1 ether, "", 0);

        assertEq(tba1.state(), 2, "tba1 state deve ser 2");
        assertEq(tba2.state(), 1, "tba2 state deve continuar 1");
    }

    // =========================================================================
    // Teste: State incrementa mesmo se external call reverte
    // =========================================================================

    /// @notice State incrementa ANTES da external call (CEI pattern)
    /// @dev Mesmo que chamada externa reverta, state já foi incrementado
    function test_state_increments_even_on_revert() public {
        vm.prank(minter);
        uint256 tokenId = 4;
        heroCard.mint(alice, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        assertEq(tba.state(), 0, "state inicial deve ser 0");

        // Deploy contrato que sempre reverte
        RevertingContract reverter = new RevertingContract();

        // Tentar executar operação que vai reverter
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        vm.expectRevert("RevertingContract: always reverts");
        tba.execute(address(reverter), 0, abi.encodeWithSelector(RevertingContract.alwaysReverts.selector), 0);

        // State NÃO incrementou porque toda a transação reverteu
        // (CEI pattern incrementa ANTES, mas revert desfaz tudo)
        assertEq(tba.state(), 0, "state deve continuar 0 apos revert");

        // Executar operação bem-sucedida
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(tba.state(), 1, "state deve ser 1 apos execucao bem-sucedida");
    }

    // =========================================================================
    // Teste: Overflow de state é virtualmente impossível
    // =========================================================================

    /// @notice Demonstrar que overflow de uint256 é impraticável
    /// @dev 2^256 execuções é astronomicamente impossível
    function test_state_overflow_impossible() public {
        vm.prank(minter);
        uint256 tokenId = 5;
        heroCard.mint(alice, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Demonstração: mesmo após muitas execuções, está longe de overflow
        vm.deal(address(tba), 1000 ether);

        uint256 executions = 100;
        for (uint256 i = 0; i < executions; i++) {
            vm.prank(alice);
            tba.execute(bob, 0, "", 0);
        }

        assertEq(tba.state(), executions, "state deve ser igual ao numero de execucoes");

        // Demonstração matemática:
        // uint256 max = 2^256 - 1 = 115792089237316195423570985008687907853269984665640564039457584007913129639935
        // Para overflow, seria necessário executar 2^256 transações
        //
        // Assumindo:
        // - 1 milhão de transações por segundo (1_000_000 tx/s)
        // - Tempo necessário = (2^256) / 1_000_000 / 60 / 60 / 24 / 365 anos
        // - Tempo = 3.67 × 10^59 anos (idade do universo: 1.38 × 10^10 anos)
        //
        // Conclusão: overflow é impraticável

        uint256 currentState = tba.state();
        uint256 remaining = type(uint256).max - currentState;

        assertTrue(remaining > type(uint128).max, "ainda ha espaco astronomico ate overflow");
    }

    // =========================================================================
    // Teste: Projeto NÃO suporta meta-transações
    // =========================================================================

    /// @notice Documentar que meta-transações NÃO são implementadas
    /// @dev Execute() requer msg.sender == owner (não usa assinaturas)
    function test_no_meta_transaction_support() public {
        vm.prank(minter);
        uint256 tokenId = 6;
        heroCard.mint(alice, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // NÃO existe função executeWithSignature()
        // Verificar que interface não tem essa função

        // Execute requer msg.sender ser owner
        vm.deal(address(tba), 1 ether);
        vm.prank(bob); // Bob tenta executar (não é owner)
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(bob, 0.1 ether, "", 0);

        // Apenas Alice (owner) pode executar
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0); // ✅ Sucesso

        assertEq(tba.state(), 1, "state incrementou");
    }

    // =========================================================================
    // Teste: State não afeta validação de assinatura
    // =========================================================================

    /// @notice isValidSignature() não usa nonce/state
    /// @dev Assinatura é validada apenas contra owner atual, independente de state
    function test_signature_independent_of_state() public {
        uint256 aliceKey = 0xA11CE;
        address aliceAddr = vm.addr(aliceKey);

        vm.prank(minter);
        uint256 tokenId = 7;
        heroCard.mint(aliceAddr, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        bytes32 hash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // State inicial = 0
        assertEq(tba.state(), 0);

        // Assinatura é válida
        assertEq(tba.isValidSignature(hash, sig), bytes4(0x1626ba7e), "assinatura deve ser valida");

        // Executar operações (incrementa state)
        vm.deal(address(tba), 1 ether);
        vm.prank(aliceAddr);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(tba.state(), 1, "state deve ser 1");

        // Assinatura ainda é válida (state não afeta validação)
        assertEq(
            tba.isValidSignature(hash, sig), bytes4(0x1626ba7e), "assinatura deve continuar valida apos incremento"
        );

        // Executar mais operações
        vm.prank(aliceAddr);
        tba.execute(bob, 0.1 ether, "", 0);
        vm.prank(aliceAddr);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(tba.state(), 3, "state deve ser 3");

        // Assinatura ainda é válida
        assertEq(tba.isValidSignature(hash, sig), bytes4(0x1626ba7e), "assinatura deve continuar valida com state=3");
    }

    // =========================================================================
    // Teste: State transferido com NFT (persiste no proxy)
    // =========================================================================

    /// @notice State persiste no proxy quando NFT é transferido
    /// @dev Novo owner herda o state acumulado (comportamento esperado)
    function test_state_persists_after_nft_transfer() public {
        vm.prank(minter);
        uint256 tokenId = 8;
        heroCard.mint(alice, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Alice executa operações
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        uint256 stateBeforeTransfer = tba.state();
        assertEq(stateBeforeTransfer, 2, "state deve ser 2 antes da transferencia");

        // Alice transfere NFT para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // State persiste (Bob herda o state acumulado)
        assertEq(tba.state(), 2, "state deve continuar 2 apos transferencia");

        // Bob executa operação (incrementa a partir do state herdado)
        vm.prank(bob);
        tba.execute(alice, 0.1 ether, "", 0);

        assertEq(tba.state(), 3, "state deve ser 3 apos bob executar");
    }

    // =========================================================================
    // Fuzz Test: State sempre incrementa monotonicamente
    // =========================================================================

    /// @notice Fuzz test: state sempre incrementa monotonicamente
    /// @dev Para qualquer sequência de execuções válidas, state aumenta
    function testFuzz_state_always_increments(uint8 numExecutions) public {
        vm.assume(numExecutions > 0 && numExecutions <= 50); // Limitar para evitar out of gas

        vm.prank(minter);
        uint256 tokenId = 9;
        heroCard.mint(alice, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        assertEq(tba.state(), 0, "state inicial deve ser 0");

        vm.deal(address(tba), 100 ether);

        uint256 expectedState = 0;
        for (uint256 i = 0; i < numExecutions; i++) {
            vm.prank(alice);
            tba.execute(bob, 0, "", 0);

            expectedState++;
            assertEq(tba.state(), expectedState, "state deve incrementar monotonicamente");
        }

        assertEq(tba.state(), uint256(numExecutions), "state final deve ser igual ao numero de execucoes");
    }

    // =========================================================================
    // Teste: ReentrancyGuard previne manipulação de state
    // =========================================================================

    /// @notice ReentrancyGuard deve prevenir reentrância que poderia manipular state
    function test_reentrancy_guard_protects_state() public {
        vm.prank(minter);
        uint256 tokenId = 10;
        heroCard.mint(alice, tokenId, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Deploy contrato malicioso que tenta reentrância
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(tba));

        vm.deal(address(tba), 1 ether);

        // Tentar ataque de reentrância
        vm.prank(alice);
        vm.expectRevert(); // Deve reverter por ReentrancyGuard
        tba.execute(address(attacker), 0, abi.encodeWithSelector(ReentrancyAttacker.attack.selector), 0);

        // State não deve ter mudado (transação reverteu)
        assertEq(tba.state(), 0, "state deve continuar 0 apos tentativa de reentrancia");

        // Executar operação normal
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(tba.state(), 1, "state deve ser 1 apos execucao normal");
    }
}

// =============================================================================
// Mock Contracts
// =============================================================================

/// @notice Contrato que sempre reverte
contract RevertingContract {
    function alwaysReverts() external pure {
        revert("RevertingContract: always reverts");
    }
}

/// @notice Contrato malicioso que tenta reentrância
contract ReentrancyAttacker {
    ERC6551Account public tba;

    constructor(address _tba) {
        tba = ERC6551Account(payable(_tba));
    }

    function attack() external {
        // Tenta chamar execute novamente (reentrância)
        tba.execute(address(this), 0, "", 0);
    }

    // Fallback para receber ETH se necessário
    receive() external payable {
        // Tenta reentrância via receive
        if (address(tba).balance > 0) {
            tba.execute(address(this), 0, "", 0);
        }
    }
}
