// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCard.sol";

/// @title ERC6551AccountSignatureTest
/// @notice Testes de segurança para validação de assinaturas ERC-1271
/// @dev Garante que assinaturas são validadas apenas contra o owner ATUAL do NFT
contract ERC6551AccountSignatureTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;

    address public minter = makeAddr("minter");
    address public bob = makeAddr("bob");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new ERC6551Account();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        vm.stopPrank();
    }

    // =========================================================================
    // Teste: Assinatura de ex-owner deve ser inválida após transferência
    // =========================================================================

    /// @notice Assinatura de ex-owner deve ser inválida após transferência do NFT
    /// @dev Protege contra replay attacks após mudança de propriedade
    function test_signature_invalid_after_transfer() public {
        // Setup: Alice possui chave privada e minta NFT
        uint256 aliceKey = 0xA11CE;
        address alice = vm.addr(aliceKey);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Alice assina mensagem enquanto é owner
        bytes32 hash = keccak256("approve action");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, hash);
        bytes memory aliceSignature = abi.encodePacked(r, s, v);

        // Assinatura é válida enquanto Alice é owner
        assertEq(
            tba.isValidSignature(hash, aliceSignature),
            bytes4(0x1626ba7e),
            "assinatura deve ser valida enquanto alice e owner"
        );

        // Alice transfere NFT para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // Assinatura de Alice agora é INVÁLIDA
        assertEq(
            tba.isValidSignature(hash, aliceSignature),
            bytes4(0xffffffff),
            "assinatura de alice deve ser invalida apos transferencia"
        );
    }

    // =========================================================================
    // Teste: Apenas owner atual pode assinar (múltiplas transferências)
    // =========================================================================

    /// @notice Múltiplas transferências: apenas owner atual pode assinar
    /// @dev Verifica que validação sempre usa owner atual, não histórico
    function test_signature_only_current_owner() public {
        // Setup: Alice e Bob com chaves privadas
        uint256 aliceKey = 0xA11CE;
        uint256 bobKey = 0xB0B;
        address alice = vm.addr(aliceKey);
        address bob = vm.addr(bobKey);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        bytes32 hash = keccak256("message");

        // Alice assina
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(aliceKey, hash);
        bytes memory aliceSig = abi.encodePacked(r1, s1, v1);

        // Bob assina
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(bobKey, hash);
        bytes memory bobSig = abi.encodePacked(r2, s2, v2);

        // Estado inicial: apenas Alice é válida
        assertEq(tba.isValidSignature(hash, aliceSig), bytes4(0x1626ba7e), "alice deve ser valida inicialmente");
        assertEq(tba.isValidSignature(hash, bobSig), bytes4(0xffffffff), "bob nao deve ser valido inicialmente");

        // Transfere Alice → Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // Agora apenas Bob é válido
        assertEq(
            tba.isValidSignature(hash, aliceSig), bytes4(0xffffffff), "alice nao deve ser valida apos transferencia"
        );
        assertEq(tba.isValidSignature(hash, bobSig), bytes4(0x1626ba7e), "bob deve ser valido apos transferencia");

        // Transfere Bob → Alice (de volta)
        vm.prank(bob);
        heroCard.transferFrom(bob, alice, tokenId);

        // Alice é válida novamente
        assertEq(tba.isValidSignature(hash, aliceSig), bytes4(0x1626ba7e), "alice deve ser valida novamente");
        assertEq(tba.isValidSignature(hash, bobSig), bytes4(0xffffffff), "bob nao deve ser valido apos devolucao");
    }

    // =========================================================================
    // Teste: TBA controlada por contrato inteligente (owner é contrato)
    // =========================================================================

    /// @notice TBA controlada por contrato que implementa ERC-1271
    /// @dev SignatureChecker deve chamar isValidSignature() recursivamente
    function test_signature_contract_owner() public {
        // Deploy contrato que sempre aprova assinaturas
        MockSignerContract contractOwner = new MockSignerContract();

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(address(contractOwner), "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        bytes32 hash = keccak256("test message");
        bytes memory dummySig = "dummy signature";

        // Como owner é um contrato com ERC-1271, deve validar via isValidSignature()
        bytes4 result = tba.isValidSignature(hash, dummySig);
        assertEq(result, bytes4(0x1626ba7e), "contrato com ERC1271 deve ser valido");
    }

    // =========================================================================
    // Teste: State/nonce não afeta validação de assinatura
    // =========================================================================

    /// @notice Verificar que state/nonce da TBA não afeta validação de assinatura
    /// @dev isValidSignature() deve ser stateless (apenas depende do owner atual)
    function test_signature_independent_of_state() public {
        uint256 aliceKey = 0xA11CE;
        address alice = vm.addr(aliceKey);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        bytes32 hash = keccak256("message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, hash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Estado inicial (state = 0)
        uint256 stateBefore = tba.state();
        assertEq(stateBefore, 0, "state inicial deve ser 0");
        assertEq(tba.isValidSignature(hash, sig), bytes4(0x1626ba7e), "assinatura deve ser valida no estado inicial");

        // Executa operação (incrementa state)
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);

        // Verificar que state incrementou
        uint256 stateAfter = tba.state();
        assertEq(stateAfter, 1, "state deve ter incrementado para 1");

        // Assinatura ainda é válida (state não afeta validação)
        assertEq(
            tba.isValidSignature(hash, sig),
            bytes4(0x1626ba7e),
            "assinatura deve continuar valida apos incremento de state"
        );

        // Executar mais operações
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);
        assertEq(tba.state(), 2, "state deve ser 2");

        // Assinatura ainda válida
        assertEq(
            tba.isValidSignature(hash, sig), bytes4(0x1626ba7e), "assinatura deve continuar valida mesmo com state=2"
        );
    }

    // =========================================================================
    // Teste: isValidSigner também valida contra owner atual
    // =========================================================================

    /// @notice isValidSigner deve validar contra owner atual (não ex-owner)
    function test_isValidSigner_after_transfer() public {
        uint256 aliceKey = 0xA11CE;
        address alice = vm.addr(aliceKey);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Alice é signer válido
        assertEq(tba.isValidSigner(alice, ""), bytes4(0x523e3260), "alice deve ser signer valido");
        assertEq(tba.isValidSigner(bob, ""), bytes4(0), "bob nao deve ser signer valido");

        // Transfere para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // Agora apenas Bob é signer válido
        assertEq(tba.isValidSigner(alice, ""), bytes4(0), "alice nao deve ser signer valido apos transferencia");
        assertEq(tba.isValidSigner(bob, ""), bytes4(0x523e3260), "bob deve ser signer valido apos transferencia");
    }

    // =========================================================================
    // Teste: Assinatura de mensagem vazia e hash zero
    // =========================================================================

    /// @notice Validar comportamento com mensagem vazia e hash zero
    function test_signature_edge_cases() public {
        uint256 aliceKey = 0xA11CE;
        address alice = vm.addr(aliceKey);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Hash zero
        bytes32 zeroHash = bytes32(0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, zeroHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertEq(
            tba.isValidSignature(zeroHash, sig), bytes4(0x1626ba7e), "deve validar hash zero com assinatura correta"
        );

        // Assinatura vazia
        bytes memory emptySig = "";
        assertEq(tba.isValidSignature(zeroHash, emptySig), bytes4(0xffffffff), "assinatura vazia deve ser invalida");
    }

    // =========================================================================
    // Teste: Fuzz - assinatura sempre validada contra owner atual
    // =========================================================================

    /// @notice Fuzz test: assinatura sempre validada contra owner atual
    function testFuzz_signature_validates_current_owner(uint256 aliceKey, bytes32 randomHash) public {
        // Bound para chaves válidas
        vm.assume(
            aliceKey > 0 && aliceKey < 115792089237316195423570985008687907852837564279074904382605163141518161494337
        );

        address alice = vm.addr(aliceKey);

        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Alice assina hash aleatório
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, randomHash);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Deve ser válida enquanto Alice é owner
        assertEq(tba.isValidSignature(randomHash, sig), bytes4(0x1626ba7e));

        // Transfere para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // Deve ser inválida após transferência
        assertEq(tba.isValidSignature(randomHash, sig), bytes4(0xffffffff));
    }
}

// =============================================================================
// Mock Contracts
// =============================================================================

/// @notice Contrato que sempre aprova assinaturas (para testar ERC-1271 recursivo)
contract MockSignerContract {
    bytes4 private constant _MAGIC = 0x1626ba7e;
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;

    function isValidSignature(bytes32, bytes memory) external pure returns (bytes4) {
        return _MAGIC;
    }

    /// @notice Implementa onERC721Received para aceitar NFTs
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return _ERC721_RECEIVED;
    }
}
