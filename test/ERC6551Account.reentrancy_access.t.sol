// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCard.sol";

/// @title ERC6551AccountReentrancyAccessTest
/// @notice Testes de segurança para reentrância e controle de acesso
/// @dev Garante que apenas owner pode executar e que reentrância é bloqueada
contract ERC6551AccountReentrancyAccessTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public tokenId;
    ERC6551Account public tba;

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new ERC6551Account();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        vm.stopPrank();

        // Mint NFT para Alice
        vm.prank(minter);
        tokenId = heroCard.mint(alice, "");
        tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));
    }

    // =========================================================================
    // Testes: Reentrância
    // =========================================================================

    /// @notice Reentrância via external call deve ser bloqueada por ReentrancyGuard
    function test_reentrancy_blocked_by_guard() public {
        // Deploy atacante que tenta reentrância
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(tba));

        vm.deal(address(tba), 1 ether);

        // Executar chamada que tenta reentrância
        vm.prank(alice);
        vm.expectRevert(); // ReentrancyGuard reverte
        tba.execute(address(attacker), 0, abi.encodeWithSelector(ReentrancyAttacker.attack.selector), 0);

        // TBA não deve ter perdido ETH
        assertEq(address(tba).balance, 1 ether, "tba nao deve ter perdido eth");
    }

    /// @notice Reentrância via fallback deve ser bloqueada
    function test_reentrancy_via_fallback_blocked() public {
        FallbackReentrancyAttacker attacker = new FallbackReentrancyAttacker(address(tba));

        vm.deal(address(tba), 1 ether);

        // Enviar ETH para attacker (trigger fallback)
        vm.prank(alice);
        vm.expectRevert(); // ReentrancyGuard reverte
        tba.execute(address(attacker), 0.1 ether, "0x1234", 0);

        // TBA não deve ter perdido ETH (transação reverteu)
        assertEq(address(tba).balance, 1 ether, "tba nao deve ter perdido eth");
    }

    /// @notice Reentrância via receive() deve ser bloqueada
    function test_reentrancy_via_receive_blocked() public {
        ReceiveReentrancyAttacker attacker = new ReceiveReentrancyAttacker(address(tba));

        vm.deal(address(tba), 1 ether);

        // Enviar ETH para attacker (trigger receive)
        vm.prank(alice);
        vm.expectRevert(); // ReentrancyGuard reverte
        tba.execute(address(attacker), 0.1 ether, "", 0);
    }

    /// @notice Múltiplas tentativas de reentrância não devem comprometer TBA
    function test_multiple_reentrancy_attempts() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(address(tba));

        vm.deal(address(tba), 1 ether);

        // Tentar reentrância múltiplas vezes
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            vm.expectRevert();
            tba.execute(address(attacker), 0, abi.encodeWithSelector(ReentrancyAttacker.attack.selector), 0);
        }

        // TBA deve estar intacta
        assertEq(address(tba).balance, 1 ether);
        assertEq(tba.state(), 0, "state nao deve ter mudado");

        // TBA deve ainda funcionar normalmente
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(bob.balance, 0.1 ether);
        assertEq(tba.state(), 1);
    }

    // =========================================================================
    // Testes: Controle de Acesso - Operadores
    // =========================================================================

    /// @notice Operador aprovado (approve) NÃO pode executar na TBA
    function test_approved_operator_cannot_execute() public {
        // Alice aprova Bob como operador do NFT
        vm.prank(alice);
        heroCard.approve(bob, tokenId);

        // Verificar que Bob é operador aprovado
        assertEq(heroCard.getApproved(tokenId), bob, "bob deve ser operador aprovado");

        // Bob tenta executar na TBA (deve falhar)
        vm.deal(address(tba), 1 ether);
        vm.prank(bob);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(bob, 0.1 ether, "", 0);

        // Apenas Alice (owner) pode executar
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(bob.balance, 0.1 ether);
    }

    /// @notice Operador global (setApprovalForAll) NÃO pode executar na TBA
    function test_approved_for_all_cannot_execute() public {
        // Alice aprova Bob como operador global
        vm.prank(alice);
        heroCard.setApprovalForAll(bob, true);

        // Verificar que Bob é operador global
        assertTrue(heroCard.isApprovedForAll(alice, bob), "bob deve ser operador global");

        // Bob tenta executar na TBA (deve falhar)
        vm.deal(address(tba), 1 ether);
        vm.prank(bob);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(bob, 0.1 ether, "", 0);

        // Apenas Alice (owner) pode executar
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(bob.balance, 0.1 ether);
    }

    // =========================================================================
    // Testes: Controle de Acesso - Transferência
    // =========================================================================

    /// @notice Ex-owner não pode executar após transferência do NFT
    function test_ex_owner_cannot_execute_after_transfer() public {
        vm.deal(address(tba), 1 ether);

        // Alice (owner) executa com sucesso
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);
        assertEq(bob.balance, 0.1 ether);

        // Alice transfere NFT para Charlie
        vm.prank(alice);
        heroCard.transferFrom(alice, charlie, tokenId);

        // Alice (ex-owner) tenta executar (deve falhar)
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(bob, 0.1 ether, "", 0);

        // Charlie (novo owner) pode executar
        vm.prank(charlie);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(bob.balance, 0.2 ether);
    }

    /// @notice Controle muda imediatamente após transferência (sem delay)
    function test_control_changes_immediately_after_transfer() public {
        vm.deal(address(tba), 1 ether);

        // Alice transfere para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // Bob pode executar imediatamente (sem delay)
        vm.prank(bob);
        tba.execute(charlie, 0.1 ether, "", 0);

        assertEq(charlie.balance, 0.1 ether);

        // Alice não pode mais executar
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(charlie, 0.1 ether, "", 0);
    }

    // =========================================================================
    // Testes: Controle de Acesso - TokenContract
    // =========================================================================

    /// @notice TokenContract pode executar (com validação própria no HeroCard)
    function test_token_contract_can_execute_via_helper() public {
        vm.deal(address(tba), 1 ether);

        // Alice chama função helper do HeroCard
        // HeroCard valida owner e depois chama tba.execute()
        vm.prank(alice);
        heroCard.withdrawEth(tokenId, payable(bob), 0.1 ether);

        assertEq(bob.balance, 0.1 ether, "bob deve ter recebido eth");
    }

    /// @notice TokenContract não pode executar sem validação própria
    /// @dev Este é um teste conceitual - HeroCard sempre valida, então não é possível testar bypass
    function test_token_contract_validates_owner_before_execute() public {
        vm.deal(address(tba), 1 ether);

        // Bob tenta chamar função do HeroCard (não é owner)
        vm.prank(bob);
        vm.expectRevert(); // HeroCard reverte com onlyOwnerOfToken
        heroCard.withdrawEth(tokenId, payable(bob), 0.1 ether);

        // TBA não foi afetada
        assertEq(address(tba).balance, 1 ether);
    }

    // =========================================================================
    // Testes: Controle de Acesso - Fuzz
    // =========================================================================

    /// @notice Fuzz: apenas owner pode executar
    function testFuzz_only_owner_can_execute(address caller) public {
        vm.assume(caller != alice); // caller não é owner
        vm.assume(caller != address(heroCard)); // caller não é tokenContract
        vm.assume(caller != address(0)); // caller não é zero address

        vm.deal(address(tba), 1 ether);

        // Caller não autorizado tenta executar
        vm.prank(caller);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(bob, 0.1 ether, "", 0);

        // Apenas Alice (owner) pode executar
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        assertEq(bob.balance, 0.1 ether);
    }

    /// @notice Fuzz: controle muda com transferências múltiplas
    function testFuzz_control_follows_nft_ownership(uint8 numTransfers) public {
        vm.assume(numTransfers > 0 && numTransfers <= 10);

        vm.deal(address(tba), 10 ether);

        address currentOwner = alice;

        for (uint256 i = 0; i < numTransfers; i++) {
            // Próximo owner (alternar entre alice, bob, charlie)
            address nextOwner;
            if (i % 3 == 0) nextOwner = bob;
            else if (i % 3 == 1) nextOwner = charlie;
            else nextOwner = alice;

            // Transferir NFT
            vm.prank(currentOwner);
            heroCard.transferFrom(currentOwner, nextOwner, tokenId);

            // Verificar que apenas nextOwner pode executar
            vm.prank(nextOwner);
            tba.execute(address(this), 0.1 ether, "", 0);

            // Owner anterior não pode mais executar
            if (currentOwner != nextOwner) {
                vm.prank(currentOwner);
                vm.expectRevert("ERC6551Account: nao autorizado");
                tba.execute(address(this), 0.1 ether, "", 0);
            }

            currentOwner = nextOwner;
        }
    }

    // =========================================================================
    // Testes: Outros Vetores
    // =========================================================================

    /// @notice Verificar que não há uso de tx.origin
    /// @dev Se tx.origin fosse usado, este teste falharia
    function test_uses_msg_sender_not_tx_origin() public {
        // Deploy contrato intermediário
        IntermediateContract intermediate = new IntermediateContract(address(tba));

        vm.deal(address(tba), 1 ether);

        // Alice chama intermediate, intermediate chama tba
        // tx.origin = alice, msg.sender (no tba) = intermediate
        vm.prank(alice);
        vm.expectRevert("ERC6551Account: nao autorizado");
        intermediate.callExecute(bob, 0.1 ether);

        // TBA corretamente valida msg.sender (intermediate), não tx.origin (alice)
    }

    /// @notice createAccount é idempotente (sem risco de reentrância)
    function test_create_account_is_idempotent() public {
        // Criar conta pela primeira vez
        address account1 = registry.createAccount(
            address(accountImpl), heroCard.DEFAULT_SALT(), block.chainid, address(heroCard), tokenId
        );

        assertTrue(account1.code.length > 0, "conta deve existir");

        // Tentar criar novamente (deve retornar mesmo endereço)
        address account2 = registry.createAccount(
            address(accountImpl), heroCard.DEFAULT_SALT(), block.chainid, address(heroCard), tokenId
        );

        assertEq(account1, account2, "deve retornar mesmo endereco");
    }

    // Fallback para receber ETH nos testes
    receive() external payable {}
}

// =============================================================================
// Mock Contracts
// =============================================================================

/// @notice Atacante que tenta reentrância explicitamente
contract ReentrancyAttacker {
    ERC6551Account public tba;

    constructor(address _tba) {
        tba = ERC6551Account(payable(_tba));
    }

    function attack() external {
        // Tenta chamar execute novamente (reentrância)
        tba.execute(address(this), 0, "", 0);
    }
}

/// @notice Atacante que tenta reentrância via fallback
contract FallbackReentrancyAttacker {
    ERC6551Account public tba;
    uint256 public callCount;

    constructor(address _tba) {
        tba = ERC6551Account(payable(_tba));
    }

    fallback() external payable {
        // Prevenir loop infinito
        if (callCount < 1) {
            callCount++;
            // Tenta reentrância
            tba.execute(address(this), 0, "", 0);
        }
    }

    receive() external payable {}
}

/// @notice Atacante que tenta reentrância via receive
contract ReceiveReentrancyAttacker {
    ERC6551Account public tba;
    uint256 public callCount;

    constructor(address _tba) {
        tba = ERC6551Account(payable(_tba));
    }

    receive() external payable {
        // Prevenir loop infinito
        if (callCount < 1) {
            callCount++;
            // Tenta reentrância
            tba.execute(address(this), 0, "", 0);
        }
    }
}

/// @notice Contrato intermediário para testar msg.sender vs tx.origin
contract IntermediateContract {
    ERC6551Account public tba;

    constructor(address _tba) {
        tba = ERC6551Account(payable(_tba));
    }

    function callExecute(address to, uint256 value) external {
        // tx.origin = caller original (alice)
        // msg.sender (no tba) = este contrato
        tba.execute(to, value, "", 0);
    }
}
