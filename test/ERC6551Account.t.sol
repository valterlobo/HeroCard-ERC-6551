// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCard.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockERC721.sol";

// ---------------------------------------------------------------------------
// Helper: contrato que sempre reverte quando recebe ETH
// ---------------------------------------------------------------------------
contract RevertOnReceive {
    error Rejected();

    receive() external payable {
        revert Rejected();
    }

    fallback() external payable {
        revert Rejected();
    }
}

// ---------------------------------------------------------------------------
// Helper: contrato que assina via ERC-1271 (para testar assinatura de contrato)
// ---------------------------------------------------------------------------
contract MockSigner {
    bytes4 private constant _MAGIC = 0x1626ba7e;

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return _MAGIC;
    }
}

/// @title ERC6551AccountTest
/// @notice Testes de cobertura de branches do ERC6551Account
contract ERC6551AccountTest is Test {
    // ── contratos ────────────────────────────────────────────────────────────
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;
    MockERC20 public gold;
    MockERC721 public sword;

    // ── atores ───────────────────────────────────────────────────────────────
    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public minter = makeAddr("minter");

    // ── setup ────────────────────────────────────────────────────────────────
    function setUp() public {
        vm.startPrank(owner);
        registry = new ERC6551Registry();
        accountImpl = new ERC6551Account();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        gold = new MockERC20("Gold Token", "GOLD");
        sword = new MockERC721("Sword NFT", "SWORD");
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(bob, 10 ether);
    }

    // ── helpers ───────────────────────────────────────────────────────────────
    /// Minta um HeroCard para `to` e devolve (tokenId, tba)
    function _mintCard(address to) internal returns (uint256 tokenId, ERC6551Account tba) {
        vm.prank(minter);
        tokenId = heroCard.mint(to, "");
        tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));
    }

    // =========================================================================
    // execute() — branch: caller não autorizado chamando DIRETAMENTE a TBA
    // (cobre o ramo "false" de require(_isValidSigner(msg.sender)))
    // =========================================================================

    /// @notice Bob (não-owner) tenta chamar execute() diretamente na TBA — deve reverter
    function test_account_execute_unauthorized_direct() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        vm.prank(bob);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(bob, 0.1 ether, "", 0);

        // tokenId usado para documentar o cartão sob teste
        assertTrue(tokenId < type(uint256).max);
    }

    // =========================================================================
    // execute() — branch: chamada interna falha (success == false)
    // (cobre o ramo "false" de `if (!success)` — bubble-up do revert)
    // =========================================================================

    /// @notice TBA tenta enviar ETH para contrato que rejeita — deve propagar o revert
    function test_account_execute_inner_call_fails() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        RevertOnReceive rejeita = new RevertOnReceive();

        vm.prank(alice);
        // A TBA propaga o revert original de RevertOnReceive
        vm.expectRevert(RevertOnReceive.Rejected.selector);
        tba.execute(address(rejeita), 0.1 ether, "", 0);
    }

    // =========================================================================
    // _isValidSigner() — branch: signer == tokenContract (não o owner)
    // (cobre o segundo return do _isValidSigner)
    // =========================================================================

    /// @notice O próprio HeroCard (tokenContract) deve ser considerado signer válido
    function test_account_isValidSigner_tokenContract() public {
        (uint256 tokenId, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        // isValidSigner com o endereço do heroCard (tokenContract) deve retornar magic value
        bytes4 result = tba.isValidSigner(address(heroCard), "");
        assertEq(result, bytes4(0x523e3260), "heroCard deve ser signer valido como tokenContract");

        // Endereço aleatório que não é nem owner nem tokenContract deve retornar 0
        bytes4 invalid = tba.isValidSigner(makeAddr("stranger"), "");
        assertEq(invalid, bytes4(0), "stranger nao deve ser signer valido");

        assertTrue(tokenId < type(uint256).max);
    }

    // =========================================================================
    // isValidSignature() — branch: assinatura válida (retorna magic value)
    // =========================================================================

    /// @notice Assinatura ECDSA do owner deve ser considerada válida (ERC-1271)
    function test_account_isValidSignature_valid() public {
        // Criar chave privada determinística
        uint256 privKey = 0xA11CE;
        address signer = vm.addr(privKey);

        // Minta para o signer (para que ele seja owner)
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(signer, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Criar hash e assinar com a chave privada do owner
        bytes32 hash = keccak256("mensagem de teste");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        bytes4 magic = tba.isValidSignature(hash, sig);
        assertEq(magic, bytes4(0x1626ba7e), "assinatura valida deve retornar magic value");
    }

    // =========================================================================
    // isValidSignature() — branch: assinatura inválida (retorna 0xffffffff)
    // =========================================================================

    /// @notice Assinatura de não-owner deve retornar valor inválido (ERC-1271)
    function test_account_isValidSignature_invalid() public {
        uint256 privKey = 0xA11CE;
        uint256 wrongKey = 0xB0B;
        address signer = vm.addr(privKey);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(signer, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        bytes32 hash = keccak256("mensagem de teste");
        // Assina com chave errada
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(wrongKey, hash);
        bytes memory badSig = abi.encodePacked(r, s, v);

        bytes4 result = tba.isValidSignature(hash, badSig);
        assertEq(result, bytes4(0xffffffff), "assinatura invalida deve retornar 0xffffffff");
    }

    // =========================================================================
    // supportsInterface() — branch: interface desconhecida → delega para super
    // =========================================================================

    /// @notice Interface desconhecida deve retornar false (ramo `super` do supportsInterface)
    function test_account_supportsInterface_unknown() public {
        (, ERC6551Account tba) = _mintCard(alice);

        // Interface inventada que não existe
        bytes4 unknown = bytes4(keccak256("InterfaceInexistente()"));
        assertFalse(tba.supportsInterface(unknown), "interface desconhecida deve retornar false");

        // IERC6551Executable (não coberto nos testes anteriores)
        assertTrue(tba.supportsInterface(type(IERC6551Executable).interfaceId), "deve suportar IERC6551Executable");
    }

    // =========================================================================
    // execute() via tokenContract — HeroCard chama execute() internamente
    // (garante cobertura do caminho signer == tokenContract no execute real)
    // =========================================================================

    /// @notice withdraw via HeroCard aciona execute() com signer == tokenContract
    function test_account_execute_via_tokenContract_path() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 2 ether);

        uint256 bobBefore = bob.balance;

        // withdrawEth chama tba.execute() com msg.sender == address(heroCard)
        vm.prank(alice);
        heroCard.withdrawEth( /* tokenId */
            0,
            payable(bob),
            1 ether
        );

        assertEq(bob.balance, bobBefore + 1 ether);
        // state deve ter incrementado
        assertEq(tba.state(), 1);
    }

    // =========================================================================
    // execute() — garante que o evento TransactionExecuted é emitido
    // =========================================================================

    function test_account_execute_emits_event() public {
        (, ERC6551Account tba) = _mintCard(alice);
        vm.deal(address(tba), 1 ether);

        vm.prank(alice);
        vm.expectEmit(true, false, false, true);
        emit ERC6551Account.TransactionExecuted(bob, 0.5 ether, "", 0);
        tba.execute(bob, 0.5 ether, "", 0);
    }
}
