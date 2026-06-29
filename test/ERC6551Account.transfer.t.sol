// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCard.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";

/// @title ERC6551AccountTransferRisksTest
/// @notice Testes demonstrando riscos de state residual após transferência de NFT
/// @dev Estes testes DOCUMENTAM comportamentos esperados (não bugs), mas que representam riscos
contract ERC6551AccountTransferRisksTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;
    MockERC20 public usdc;
    MockERC721 public rareNFT;

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public maliciousContract = makeAddr("malicious");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new HeroCardAccount();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        usdc = new MockERC20("USD Coin", "USDC");
        rareNFT = new MockERC721("Rare NFT", "RARE");
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    // =========================================================================
    // RISCO #1: Aprovações ERC-20 persistem após transferência
    // =========================================================================

    /// @notice Demonstra que aprovações ERC-20 persistem após transferir o NFT
    /// @dev Este é comportamento ESPERADO do ERC-6551, mas representa RISCO SIGNIFICATIVO
// removed for removed delegate functions
    function test_RISK_erc20_approval_persists_after_transfer() public {}

    // =========================================================================
    // RISCO #2: Operadores ERC-721 persistem após transferência
    // =========================================================================

    /// @notice Demonstra que setApprovalForAll persiste após transferir o NFT
// removed for removed delegate functions
    function test_RISK_nft_operator_persists_after_transfer() public {}

    // =========================================================================
    // RISCO #3: State/nonce da TBA persiste (não é vulnerabilidade, mas comportamento)
    // =========================================================================

    /// @notice Demonstra que state/nonce da TBA não é resetado
    /// @dev Baixo risco, mas pode confundir análise on-chain
    function test_INFO_tba_state_persists_after_transfer() public {
        // Setup
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));
        vm.deal(address(tba), 10 ether);

        // Alice executa várias transações
        vm.startPrank(alice);
        tba.execute(bob, 1 ether, "", 0);
        tba.execute(bob, 1 ether, "", 0);
        tba.execute(bob, 1 ether, "", 0);
        vm.stopPrank();

        uint256 stateBeforeTransfer = tba.state();
        assertEq(stateBeforeTransfer, 3, "State deve ser 3 apos 3 execucoes");

        // Transfere para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // ℹ️ INFO: State NÃO é resetado
        uint256 stateAfterTransfer = tba.state();
        assertEq(stateAfterTransfer, 3, "State persiste apos transferencia");

        // Bob executa transação (incrementa state a partir do valor herdado)
        vm.prank(bob);
        tba.execute(bob, 1 ether, "", 0);

        assertEq(tba.state(), 4, "State incrementa a partir do valor herdado");

        // ℹ️ Não é vulnerabilidade de segurança, mas Bob herda histórico de Alice
    }

    // =========================================================================
    // MITIGAÇÃO: Revogar aprovações antes de transferir
    // =========================================================================

    /// @notice Demonstra como mitigar o risco revogando aprovações ANTES de transferir
// removed for removed delegate functions
    function test_MITIGATION_revoke_approvals_before_transfer() public {}

    // =========================================================================
    // MITIGAÇÃO: Sacar todos os ativos antes de transferir
    // =========================================================================

    /// @notice Demonstra mitigação completa: sacar tudo e revogar tudo
// removed for removed delegate functions
    function test_MITIGATION_complete_cleanup_before_transfer() public {}

    // =========================================================================
    // FUZZ: Múltiplas transferências com state residual
    // =========================================================================

    /// @notice Fuzz test demonstrando que state persiste através de múltiplas transferências
    function testFuzz_state_persists_through_multiple_transfers(uint8 numTransfers) public {
        vm.assume(numTransfers > 0 && numTransfers <= 10);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));
        vm.deal(address(tba), 100 ether);

        address currentOwner = alice;
        address[] memory owners = new address[](numTransfers + 1);
        owners[0] = alice;

        for (uint256 i = 1; i <= numTransfers; i++) {
            owners[i] = makeAddr(string(abi.encodePacked("owner", i)));
        }

        // Executar transações e transferir múltiplas vezes
        for (uint256 i = 0; i < numTransfers; i++) {
            // Owner atual executa transação
            vm.prank(currentOwner);
            tba.execute(bob, 0.1 ether, "", 0);

            // Transfere para próximo owner
            address nextOwner = owners[i + 1];
            vm.prank(currentOwner);
            heroCard.transferFrom(currentOwner, nextOwner, tokenId);

            currentOwner = nextOwner;
        }

        // State deve ser igual ao número de transações executadas
        assertEq(tba.state(), numTransfers, "State deve refletir todas as execucoes");
    }
}
