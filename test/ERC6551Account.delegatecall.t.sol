// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCard.sol";

/// @title ERC6551AccountDelegatecallTest
/// @notice Testes de segurança para operações de execução (CALL vs DELEGATECALL)
/// @dev Garante que apenas CALL é permitido, protegendo contra corrupção de storage
contract ERC6551AccountDelegatecallTest is Test {
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
    // Teste: Apenas operation = 0 (CALL) é aceita
    // =========================================================================

    /// @notice Apenas CALL (operation = 0) deve ser aceito
    /// @dev DELEGATECALL, CREATE, CREATE2 devem ser rejeitados
    function test_only_call_operation_accepted() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        vm.deal(address(tba), 1 ether);

        // ✅ operation = 0 (CALL) → Aceito
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);
        assertEq(bob.balance, 0.1 ether, "call deve ter sucesso");

        // ❌ operation = 1 (DELEGATECALL) → Rejeitado
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.execute(bob, 0, "", 1);

        // ❌ operation = 2 (CREATE) → Rejeitado
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.execute(bob, 0, "", 2);

        // ❌ operation = 3 (CREATE2) → Rejeitado
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.execute(bob, 0, "", 3);
    }

    // =========================================================================
    // Teste: Tentativa de delegatecall não afeta storage da TBA
    // =========================================================================

    /// @notice Tentativa de delegatecall (revertida) não deve corromper storage
    /// @dev State deve permanecer inalterado após revert
    function test_delegatecall_attempt_does_not_corrupt_storage() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        uint256 stateBefore = tba.state();
        assertEq(stateBefore, 0, "state inicial deve ser 0");

        // Deploy contrato malicioso que tentaria corromper storage
        MaliciousStorageCorruptor malicious = new MaliciousStorageCorruptor();

        // Tentar delegatecall (vai reverter)
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.execute(address(malicious), 0, abi.encodeWithSelector(MaliciousStorageCorruptor.corrupt.selector), 1);

        // Storage não foi afetado (transação reverteu ANTES de executar)
        assertEq(tba.state(), stateBefore, "state nao deve ter mudado");

        // Executar operação válida para verificar que TBA ainda funciona
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(tba.state(), 1, "state deve incrementar normalmente");
        assertEq(bob.balance, 0.1 ether, "tba deve funcionar normalmente");
    }

    // =========================================================================
    // Teste: CALL não pode afetar storage da TBA
    // =========================================================================

    /// @notice CALL executa no contexto do contrato chamado, não da TBA
    /// @dev Storage da TBA permanece isolado
    function test_call_cannot_affect_tba_storage() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        uint256 tbaStateBefore = tba.state();
        assertEq(tbaStateBefore, 0, "tba state inicial deve ser 0");

        // Deploy contrato que lê seu próprio storage slot 0
        StorageReader reader = new StorageReader();

        // Executar via CALL (operation = 0)
        vm.prank(alice);
        bytes memory result =
            tba.execute(address(reader), 0, abi.encodeWithSelector(StorageReader.readSlot0.selector), 0);

        uint256 readerSlot = abi.decode(result, (uint256));

        // Valor lido é do contrato reader (123), não da TBA (0)
        assertEq(readerSlot, 123, "call deve ler storage do contrato chamado");
        assertEq(tba.state(), 1, "tba state deve ter incrementado para 1");
        assertNotEq(readerSlot, tbaStateBefore, "valores devem ser diferentes");
    }

    // =========================================================================
    // Teste: Tentativa de selfdestruct não afeta TBA
    // =========================================================================

    /// @notice Selfdestruct via CALL afeta apenas o contrato chamado
    /// @dev TBA permanece intacta
    function test_selfdestruct_attempt_does_not_destroy_tba() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        vm.deal(address(tba), 1 ether);

        // Deploy contrato com selfdestruct
        SelfDestructContract destroyer = new SelfDestructContract();
        vm.deal(address(destroyer), 0.5 ether);

        uint256 destroyerBalanceBefore = address(destroyer).balance;
        uint256 tbaBalanceBefore = address(tba).balance;

        // Executar via CALL (operation = 0) - não DELEGATECALL
        vm.prank(alice);
        tba.execute(address(destroyer), 0, abi.encodeWithSelector(SelfDestructContract.destroy.selector, bob), 0);

        // TBA permanece intacta
        assertTrue(address(tba).code.length > 0, "tba deve continuar existindo");
        assertEq(tba.state(), 1, "tba deve ter incrementado state");

        // Pós-EIP-6780 (Cancun): selfdestruct apenas envia ETH, não destrói código
        // Pré-Cancun: código seria destruído mas isso afetaria apenas destroyer, não TBA

        // Bob recebeu ETH do destroyer (não da TBA)
        assertEq(bob.balance, destroyerBalanceBefore, "bob deve ter recebido ETH do destroyer");
        assertEq(address(tba).balance, tbaBalanceBefore, "tba nao deve ter perdido ETH");
    }

    // =========================================================================
    // Teste: Validação de operation acontece ANTES da execução
    // =========================================================================

    /// @notice Validação de operation deve acontecer ANTES de incrementar state
    /// @dev State não deve mudar se operation é inválida
    function test_operation_validation_before_state_change() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        uint256 stateBefore = tba.state();

        // Tentar operação inválida
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.execute(bob, 0, "", 1);

        // State não mudou (validação aconteceu ANTES)
        assertEq(tba.state(), stateBefore, "state nao deve ter mudado");

        // Executar operação válida
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(tba.state(), 1, "state deve incrementar apenas com operacao valida");
    }

    // =========================================================================
    // Teste: Autorização validada ANTES de verificar operation
    // =========================================================================

    /// @notice Autorização deve ser validada antes de verificar operation
    /// @dev Atacante não autorizado não pode sequer tentar delegatecall
    function test_authorization_checked_before_operation() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Bob (não owner) tenta delegatecall
        vm.prank(bob);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(address(this), 0, "", 1);

        // Mesmo com operation = 0, Bob não é autorizado
        vm.prank(bob);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(address(this), 0, "", 0);
    }

    // =========================================================================
    // Fuzz Test: Apenas operation = 0 é aceita
    // =========================================================================

    /// @notice Fuzz test: qualquer operation != 0 deve ser rejeitada
    function testFuzz_only_operation_zero_accepted(uint8 operation) public {
        vm.assume(operation != 0);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        vm.prank(alice);
        vm.expectRevert("ERC6551Account: operacao nao suportada");
        tba.execute(bob, 0, "", operation);
    }

    // =========================================================================
    // Fuzz Test: CALL sempre executa no contexto do destino
    // =========================================================================

    /// @notice Fuzz test: CALL sempre executa no contexto do destino, não da TBA
    function testFuzz_call_executes_in_target_context(uint96 value) public {
        vm.assume(value > 0 && value <= 0.5 ether);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        vm.deal(address(tba), 1 ether);

        uint256 bobBalanceBefore = bob.balance;
        uint256 tbaStateBefore = tba.state();

        // Executar CALL para enviar ETH para bob
        vm.prank(alice);
        tba.execute(bob, value, "", 0);

        // Bob recebeu ETH (execução foi no contexto dele)
        assertEq(bob.balance, bobBalanceBefore + value, "bob deve ter recebido ETH");

        // TBA incrementou state (comportamento normal)
        assertEq(tba.state(), tbaStateBefore + 1, "tba deve ter incrementado state");
    }

    // =========================================================================
    // Teste: Múltiplas tentativas de operações inválidas
    // =========================================================================

    /// @notice Múltiplas tentativas de operações inválidas não afetam TBA
    function test_multiple_invalid_operations_do_not_affect_tba() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        uint256 stateBefore = tba.state();

        // Tentar várias operações inválidas
        for (uint8 op = 1; op <= 10; op++) {
            vm.prank(alice);
            vm.expectRevert("ERC6551Account: operacao nao suportada");
            tba.execute(bob, 0, "", op);
        }

        // State não mudou
        assertEq(tba.state(), stateBefore, "state nao deve ter mudado apos multiplas tentativas");

        // TBA ainda funciona normalmente
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(tba.state(), 1, "tba deve funcionar normalmente");
    }
}

// =============================================================================
// Mock Contracts
// =============================================================================

/// @notice Contrato malicioso que tentaria corromper storage via delegatecall
contract MaliciousStorageCorruptor {
    uint256 public maliciousData = 0xDEADBEEF;

    function corrupt() external {
        // Se fosse executado via delegatecall, sobrescreveria o slot 0 da TBA (_state)
        maliciousData = 0xBADC0DE;
    }
}

/// @notice Contrato que lê seu próprio storage slot 0
contract StorageReader {
    uint256 private data = 123; // Slot 0

    function readSlot0() external view returns (uint256) {
        return data;
    }
}

/// @notice Contrato com selfdestruct
contract SelfDestructContract {
    function destroy(address payable beneficiary) external {
        assembly {
            selfdestruct(beneficiary)
        }
    }

    receive() external payable {}
}
