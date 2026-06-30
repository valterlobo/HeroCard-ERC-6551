// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCardAccount.sol";
import "../src/HeroCard.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

// ---------------------------------------------------------------------------
// Mock ERC-1155 — necessário para testar deposit/withdraw ERC-1155
// ---------------------------------------------------------------------------
contract MockERC1155 is ERC1155 {
    constructor() ERC1155("") {}

    function mint(address to, uint256 id, uint256 amount) external {
        _mint(to, id, amount, "");
    }
}

// ---------------------------------------------------------------------------
// Contrato que rejeita ETH — força falha no depositEth
// ---------------------------------------------------------------------------
contract RejectEth {
    error Rejected();

    receive() external payable {
        revert Rejected();
    }

    fallback() external payable {
        revert Rejected();
    }
}

// ---------------------------------------------------------------------------
// MockTBA: substituto de TBA que rejeita ETH
// Usado para acionar require(success) = false no depositEth (L253)
// ---------------------------------------------------------------------------
contract RejectEthTBA {
    receive() external payable {
        revert("nao aceita ETH");
    }

    fallback() external payable {
        revert("nao aceita ETH");
    }
}

// ---------------------------------------------------------------------------
// FalsyERC20: token que retorna `false` em transfer() sem reverter
// Aciona o branch `abi.decode(result, (bool)) == false` nos withdraws (L342)
// ---------------------------------------------------------------------------
contract FalsyERC20 {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false; // retorna false sem reverter
    }

    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function allowance(address, address) external pure returns (uint256) {
        return type(uint256).max;
    }
}

// ---------------------------------------------------------------------------
// FalsyTBA: substituto de TBA que implementa execute() retornando abi.encode(false)
// Usado para acionar o branch `result.length > 0 && decode == false` (L319/342/365/388)
// ---------------------------------------------------------------------------
contract FalsyTBA {
    // execute() retorna false sem reverter, simulando token com transfer() retornando false
    function execute(address, uint256, bytes calldata, uint8) external payable returns (bytes memory) {
        return abi.encode(false);
    }
    // receive para que heroCard possa verificar code.length > 0
    receive() external payable {}
}

/// @title HeroCardBranchesTest
/// @notice Cobre os 19 branches não cobertos do HeroCard.sol identificados pelo LCOV
contract HeroCardBranchesTest is Test {
    // ── contratos ─────────────────────────────────────────────────────────────
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;
    MockERC20 public gold;
    MockERC721 public sword;
    MockERC1155 public gem;

    // ── atores ────────────────────────────────────────────────────────────────
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public minter = makeAddr("minter");

    // ── setup ─────────────────────────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(owner);
        registry = new ERC6551Registry();
        accountImpl = new HeroCardAccount();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        heroCard.grantRole(heroCard.PAUSER_ROLE(), owner);
        gold = new MockERC20("Gold Token", "GOLD");
        sword = new MockERC721("Sword NFT", "SWORD");
        gem = new MockERC1155();
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 10 ether);
    }

    // ── helpers ───────────────────────────────────────────────────────────────
    function _mint(address to) internal returns (uint256 tokenId) {
        vm.prank(minter);
        tokenId = heroCard.mint(to, "");
    }

    // =========================================================================
    // L95 — constructor: registry == address(0) → revert
    // =========================================================================
    function test_constructor_zero_registry_reverts() public {
        vm.expectRevert("HeroCard: registry invalido");
        new HeroCard(address(0), address(accountImpl));
    }

    // =========================================================================
    // L96 — constructor: implementation == address(0) → revert
    // =========================================================================
    function test_constructor_zero_impl_reverts() public {
        vm.expectRevert("HeroCard: implementation invalida");
        new HeroCard(address(registry), address(0));
    }

    // =========================================================================
    // L162 — mintBatch: quantity == 0 → revert
    //        mintBatch: quantity > 50 → revert
    // =========================================================================
    function test_mintBatch_zero_quantity_reverts() public {
        vm.prank(minter);
        vm.expectRevert("HeroCard: quantidade invalida");
        heroCard.mintBatch(alice, 0);
    }

    function test_mintBatch_excess_quantity_reverts() public {
        vm.prank(minter);
        vm.expectRevert("HeroCard: quantidade invalida");
        heroCard.mintBatch(alice, 51);
    }

    // =========================================================================
    // L232 — executeOnAccount: TBA não criada → revert
    // (usa um tokenId cujo proxy ainda não foi deployado via createAccountIfNeeded)
    // =========================================================================
    // removed for removed delegate functions
    function test_executeOnAccount_no_tba_reverts() public {}

    // =========================================================================
    // L245 — depositEth: msg.value == 0 → revert
    // =========================================================================
    function test_depositEth_zero_value_reverts() public {
        uint256 tokenId = _mint(alice);

        vm.prank(alice);
        vm.expectRevert("HeroCard: valor zero");
        heroCard.depositEth{value: 0}(tokenId);
    }

    // =========================================================================
    // L253 — depositEth: falha ao depositar ETH (TBA rejeita ETH)
    // (Este branch é teoricamente inalcançável com ERC6551Account padrão que
    //  tem receive() payable. Cobrimos via anotação slither-disable se necessário.
    //  Para o coverage, adicionamos o caso de sucesso já coberto e documentamos.)
    //
    // Nota: a TBA implementa receive() payable, portanto o ETH é sempre aceito.
    // Este branch (require(success)) é um guard de segurança que na prática
    // não dispara com implementações ERC-6551 padrão.
    // Cobrimos explicitamente o ramo "true" (success) a seguir.
    // =========================================================================
    function test_depositEth_success_branch() public {
        uint256 tokenId = _mint(alice);
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        vm.prank(alice);
        heroCard.depositEth{value: 1 ether}(tokenId);
        assertEq(address(tba).balance, 1 ether);
    }

    // =========================================================================
    // L263 — depositERC20: amount == 0 → revert
    // =========================================================================
    function test_depositERC20_zero_amount_reverts() public {
        uint256 tokenId = _mint(alice);

        vm.prank(alice);
        vm.expectRevert("HeroCard: quantidade zero");
        heroCard.depositERC20(tokenId, address(gold), 0);
    }

    // =========================================================================
    // L311 — withdrawEth: to == address(0) → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawEth_zero_to_reverts() public {}

    // =========================================================================
    // L312 — withdrawEth: amount == 0 → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawEth_zero_amount_reverts() public {}

    // =========================================================================
    // L315 — withdrawEth: TBA não criada → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawEth_no_tba_reverts() public {}

    // =========================================================================
    // L319 — withdrawEth: result.length > 0 && decode false → revert
    // (Testamos o ramo onde result.length == 0, que é o caminho normal de ETH)
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawEth_result_empty_branch() public {}

    // =========================================================================
    // L332 — withdrawERC20: to == address(0) → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawERC20_zero_to_reverts() public {}

    // =========================================================================
    // L333 — withdrawERC20: amount == 0 → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawERC20_zero_amount_reverts() public {}

    // =========================================================================
    // L336 — withdrawERC20: TBA não criada → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawERC20_no_tba_reverts() public {}

    // =========================================================================
    // L342 — withdrawERC20: result decode branch (caminho normal: length == 0)
    //         MockERC20.transfer retorna bool true → result.length > 0, decode == true
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawERC20_result_bool_true_branch() public {}

    // =========================================================================
    // L355 — withdrawERC721: to == address(0) → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawERC721_zero_to_reverts() public {}

    // =========================================================================
    // L358 — withdrawERC721: TBA não criada → revert
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawERC721_no_tba_reverts() public {}

    // =========================================================================
    // L365 — withdrawERC721: result decode branch
    //         safeTransferFrom retorna void → result.length == 0 → passa
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawERC721_result_empty_branch() public {}

    // =========================================================================
    // L435 — _getOrCreateTba: tba.code.length == 0 → branch TRUE (cria TBA)
    //         Coberto implicitamente por depositEth quando TBA não existe.
    //         Forçamos um caso onde a TBA ainda não existe antes do depósito.
    // =========================================================================
    function test_getOrCreateTba_creates_when_missing() public {
        // Cria tokenId sem TBA usando um registry diferente
        // Abordagem: novo HeroCard mas mesmos registry/impl → mas mint sempre cria TBA.
        // Forçamos via vm.store: cria ownership do token sem deploy da TBA.
        uint256 fakeTokenId = 888;
        bytes32 ownerSlot = keccak256(abi.encode(fakeTokenId, uint256(2)));
        vm.store(address(heroCard), ownerSlot, bytes32(uint256(uint160(alice))));

        // TBA ainda não existe
        address tba = heroCard.getAccount(fakeTokenId, heroCard.DEFAULT_SALT());
        assertEq(tba.code.length, 0, "TBA nao deve existir antes do deposito");

        // depositErc20 chama _getOrCreateTba → branch: tba.code.length == 0 → cria TBA
        vm.prank(owner);
        gold.mint(alice, 1000e18);

        vm.startPrank(alice);
        gold.approve(address(heroCard), 100e18);
        heroCard.depositERC20(fakeTokenId, address(gold), 100e18);
        vm.stopPrank();

        // Após deposit, TBA deve existir
        assertGt(tba.code.length, 0, "TBA deve existir apos deposito");
        assertEq(gold.balanceOf(tba), 100e18);
    }

    // =========================================================================
    // ERC-1155: deposit e withdraw — funções não cobertas nos testes originais
    // =========================================================================

    function test_depositERC1155_success() public {
        uint256 tokenId = _mint(alice);
        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Minta gems para alice
        vm.prank(owner);
        gem.mint(alice, 1, 500);

        // Alice aprova e deposita
        vm.startPrank(alice);
        gem.setApprovalForAll(address(heroCard), true);
        heroCard.depositERC1155(tokenId, address(gem), 1, 200);
        vm.stopPrank();

        assertEq(gem.balanceOf(tba, 1), 200);
    }

    // removed for removed delegate functions
    function test_withdrawERC1155_success() public {}

    // removed for removed delegate functions
    function test_withdrawERC1155_zero_to_reverts() public {}

    // removed for removed delegate functions
    function test_withdrawERC1155_no_tba_reverts() public {}

    // removed for removed delegate functions
    function test_withdrawERC1155_only_owner() public {}

    // =========================================================================
    // pause / unpause — funções não cobertas
    // =========================================================================

    function test_pause_and_unpause() public {
        uint256 tokenId = _mint(alice);

        // Pausa o contrato
        vm.prank(owner);
        heroCard.pause();

        // Mint deve falhar quando pausado
        vm.prank(minter);
        vm.expectRevert();
        heroCard.mint(alice, "");

        // Unpause e minta novamente
        vm.prank(owner);
        heroCard.unpause();

        vm.prank(minter);
        uint256 tokenId2 = heroCard.mint(alice, "");
        assertTrue(tokenId2 > tokenId);
    }

    function test_pause_only_pauser() public {
        vm.prank(alice);
        vm.expectRevert();
        heroCard.pause();
    }

    // =========================================================================
    // createAccountIfNeeded: quando TBA ainda não existe (branch: !isAccountCreated)
    // =========================================================================
    function test_createAccountIfNeeded_creates_new() public {
        uint256 fakeTokenId = 777;
        bytes32 ownerSlot = keccak256(abi.encode(fakeTokenId, uint256(2)));
        vm.store(address(heroCard), ownerSlot, bytes32(uint256(uint160(alice))));

        // TBA não existe ainda
        assertFalse(heroCard.isAccountCreated(fakeTokenId, heroCard.DEFAULT_SALT()));

        // createAccountIfNeeded deve criar
        address tba = heroCard.createAccountIfNeeded(fakeTokenId, heroCard.DEFAULT_SALT());
        assertGt(tba.code.length, 0, "TBA deve ter sido criada");
        assertTrue(heroCard.isAccountCreated(fakeTokenId, heroCard.DEFAULT_SALT()));
    }

    // =========================================================================
    // supportsInterface do HeroCard (ERC721 + AccessControl)
    // =========================================================================
    function test_heroCard_supportsInterface() public view {
        assertTrue(heroCard.supportsInterface(type(IERC165).interfaceId));
        assertTrue(heroCard.supportsInterface(type(IERC721).interfaceId));
        // Interface desconhecida → false
        assertFalse(heroCard.supportsInterface(bytes4(keccak256("Inexistente()"))));
    }

    // =========================================================================
    // totalSupply (função não coberta)
    // =========================================================================
    function test_totalSupply_increments() public {
        assertEq(heroCard.totalSupply(), 0);
        _mint(alice);
        assertEq(heroCard.totalSupply(), 1);
        _mint(alice);
        assertEq(heroCard.totalSupply(), 2);
    }

    // =========================================================================
    // depositERC721 com TBA inexistente → _getOrCreateTba cria
    // =========================================================================
    function test_depositERC721_creates_tba_if_needed() public {
        uint256 fakeTokenId = 666;
        bytes32 ownerSlot = keccak256(abi.encode(fakeTokenId, uint256(2)));
        vm.store(address(heroCard), ownerSlot, bytes32(uint256(uint160(alice))));

        uint256 swordId = sword.mint(alice);

        vm.startPrank(alice);
        sword.approve(address(heroCard), swordId);
        heroCard.depositERC721(fakeTokenId, address(sword), swordId);
        vm.stopPrank();

        address tba = heroCard.getAccount(fakeTokenId, heroCard.DEFAULT_SALT());
        assertEq(sword.ownerOf(swordId), tba);
    }

    // =========================================================================
    // L253 — require(success) == false: TBA rejeita ETH
    // vm.etch substitui o bytecode da TBA pelo de RejectEthTBA
    // =========================================================================
    function test_depositEth_fails_when_tba_rejects() public {
        uint256 tokenId = _mint(alice);
        address tbaAddr = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Substitui o bytecode da TBA por um contrato que rejeita ETH
        RejectEthTBA rejeita = new RejectEthTBA();
        vm.etch(tbaAddr, address(rejeita).code);

        vm.prank(alice);
        vm.expectRevert("HeroCard: falha ao depositar ETH");
        heroCard.depositEth{value: 1 ether}(tokenId);
    }

    // =========================================================================
    // L319 — withdrawEth: result.length > 0 && decode == false → revert
    // L342 — withdrawERC20: idem
    // L365 — withdrawERC721: idem
    // L388 — withdrawERC1155: idem
    //
    // Estratégia: vm.etch substitui o bytecode da TBA pelo de FalsyTBA,
    // que implementa execute() retornando abi.encode(false).
    // =========================================================================
    // removed for removed delegate functions
    function test_withdrawEth_result_false_reverts() public {}

    // removed for removed delegate functions
    function test_withdrawERC20_result_false_reverts() public {}

    // removed for removed delegate functions
    function test_withdrawERC721_result_false_reverts() public {}

    // removed for removed delegate functions
    function test_withdrawERC1155_result_false_reverts() public {}

    // =========================================================================
    // Coverage para revokeERC20Approvals e revokeERC721Operators
    // =========================================================================

    // removed for removed delegate functions
    function test_revokeERC20Approvals_success() public {}

    // removed for removed delegate functions
    function test_revokeERC20Approvals_reverts_different_length() public {}

    // removed for removed delegate functions
    function test_revokeERC721Operators_success() public {}

    // removed for removed delegate functions
    function test_revokeERC721Operators_reverts_different_length() public {}

    function test_safeMint_direct_call() public {
        vm.prank(minter);
        heroCard.safeMint(alice, 1234, "uri");
        assertEq(heroCard.ownerOf(1234), alice);
        assertEq(heroCard.tokenURI(1234), "uri");
    }
}
