// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCard.sol";

/// @title ERC6551AccountInitializationTest
/// @notice Testes de segurança para verificar que NÃO há vulnerabilidades de inicialização
/// @dev Demonstra que o padrão "immutable data" é seguro por design
contract ERC6551AccountInitializationTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;
    HeroCard public heroCard;

    address public minter = makeAddr("minter");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public attacker = makeAddr("attacker");

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new ERC6551Account();
        heroCard = new HeroCard(address(registry), address(accountImpl));
        heroCard.grantRole(heroCard.MINTER_ROLE(), minter);
        vm.stopPrank();

        vm.deal(alice, 100 ether);
        vm.deal(attacker, 100 ether);
    }

    // =========================================================================
    // TESTE: Não há função initialize()
    // =========================================================================

    /// @notice Verifica que não existe função initialize() no contrato
    /// @dev Tenta chamar initialize() via low-level call - deve falhar
    function test_no_initialize_function() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tbaAddress = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Tenta chamar initialize(address) - função não existe
        bytes memory initCall = abi.encodeWithSignature("initialize(address)", attacker);

        vm.prank(attacker);
        (bool success,) = tbaAddress.call(initCall);

        // ✅ Deve falhar porque função não existe
        assertFalse(success, "initialize() nao deve existir");
    }

    /// @notice Testa variações de funções de inicialização comuns
    function test_no_common_init_functions() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tbaAddress = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Lista de funções de inicialização comuns
        bytes[] memory initCalls = new bytes[](5);
        initCalls[0] = abi.encodeWithSignature("initialize()");
        initCalls[1] = abi.encodeWithSignature("initialize(address)", attacker);
        initCalls[2] = abi.encodeWithSignature("init()");
        initCalls[3] = abi.encodeWithSignature("setUp()");
        initCalls[4] = abi.encodeWithSignature("__init__()");

        for (uint256 i = 0; i < initCalls.length; i++) {
            vm.prank(attacker);
            (bool success,) = tbaAddress.call(initCalls[i]);

            // ✅ Todas devem falhar
            assertFalse(success, string(abi.encodePacked("Init function ", i, " nao deve existir")));
        }
    }

    // =========================================================================
    // TESTE: Dados imutáveis não podem ser modificados
    // =========================================================================

    /// @notice Verifica que dados imutáveis permanecem constantes
    function test_immutable_data_cannot_change() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Lê dados iniciais
        (uint256 chainId1, address tokenContract1, uint256 tokenId1) = tba.token();

        assertEq(chainId1, block.chainid, "ChainId deve ser correto");
        assertEq(tokenContract1, address(heroCard), "TokenContract deve ser HeroCard");
        assertEq(tokenId1, tokenId, "TokenId deve corresponder");

        // Executa várias operações (incrementa state)
        vm.deal(address(tba), 10 ether);

        vm.prank(alice);
        tba.execute(bob, 1 ether, "", 0);

        vm.prank(alice);
        tba.execute(bob, 1 ether, "", 0);

        // Lê dados novamente
        (uint256 chainId2, address tokenContract2, uint256 tokenId2) = tba.token();

        // ✅ Dados devem ser idênticos (imutáveis)
        assertEq(chainId1, chainId2, "ChainId nao deve mudar");
        assertEq(tokenContract1, tokenContract2, "TokenContract nao deve mudar");
        assertEq(tokenId1, tokenId2, "TokenId nao deve mudar");
    }

    /// @notice Tenta sobrescrever dados via execute() malicioso
    function test_cannot_overwrite_via_execute() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Lê dados iniciais
        (uint256 chainIdBefore, address tokenContractBefore, uint256 tokenIdBefore) = tba.token();

        // Tenta chamar funções maliciosas que poderiam sobrescrever storage
        bytes[] memory maliciousCalls = new bytes[](3);
        maliciousCalls[0] = abi.encodeWithSignature("sstore(uint256,uint256)", 0, uint256(uint160(attacker)));
        maliciousCalls[1] = abi.encodeWithSignature("setOwner(address)", attacker);
        maliciousCalls[2] = abi.encodeWithSignature("updateToken(address,uint256)", attacker, 999);

        for (uint256 i = 0; i < maliciousCalls.length; i++) {
            vm.prank(alice);
            vm.expectRevert(); // Funções não existem
            tba.execute(address(tba), 0, maliciousCalls[i], 0);
        }

        // Lê dados após tentativas de ataque
        (uint256 chainIdAfter, address tokenContractAfter, uint256 tokenIdAfter) = tba.token();

        // ✅ Dados devem permanecer inalterados
        assertEq(chainIdBefore, chainIdAfter);
        assertEq(tokenContractBefore, tokenContractAfter);
        assertEq(tokenIdBefore, tokenIdAfter);
    }

    // =========================================================================
    // TESTE: Frontrunning de createAccount() é inofensivo
    // =========================================================================

    /// @notice Verifica que atacante não ganha controle por frontrunning
    function test_frontrun_createAccount_is_harmless() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        address expectedTBA = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // ⚠️ Atacante tenta frontrun criando TBA antes do owner legítimo
        vm.prank(attacker);
        address attackerCreatedTBA = heroCard.createAccountIfNeeded(tokenId, heroCard.DEFAULT_SALT());

        // ✅ Endereço é determinístico (CREATE2 sempre retorna mesmo endereço)
        assertEq(attackerCreatedTBA, expectedTBA, "Endereco deve ser deterministico");

        // ✅ Alice ainda é o owner (via ownerOf(tokenId))
        ERC6551Account tba = ERC6551Account(payable(expectedTBA));
        assertEq(tba.isValidSigner(alice, ""), bytes4(0x523e3260), "Alice deve ser signer valido");
        assertEq(tba.isValidSigner(attacker, ""), bytes4(0), "Attacker nao deve ser signer valido");

        // ✅ Atacante não pode executar operações
        vm.prank(attacker);
        vm.expectRevert("ERC6551Account: nao autorizado");
        tba.execute(attacker, 0, "", 0);

        // ✅ Alice pode executar normalmente
        vm.deal(address(tba), 1 ether);
        vm.prank(alice);
        tba.execute(bob, 0.1 ether, "", 0);
        assertEq(bob.balance, 0.1 ether);
    }

    /// @notice Verifica que criar TBA múltiplas vezes é idempotente
    function test_createAccount_is_idempotent() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        // Cria TBA primeira vez
        address tba1 = heroCard.createAccountIfNeeded(tokenId, heroCard.DEFAULT_SALT());

        // Cria TBA segunda vez (deve retornar mesmo endereço)
        address tba2 = heroCard.createAccountIfNeeded(tokenId, heroCard.DEFAULT_SALT());

        // Cria TBA terceira vez por atacante
        vm.prank(attacker);
        address tba3 = heroCard.createAccountIfNeeded(tokenId, heroCard.DEFAULT_SALT());

        // ✅ Todos devem ser o mesmo endereço
        assertEq(tba1, tba2, "TBA deve ser idempotente");
        assertEq(tba2, tba3, "TBA deve ser idempotente mesmo com caller diferente");

        // ✅ Alice ainda controla
        ERC6551Account tba = ERC6551Account(payable(tba1));
        assertEq(tba.isValidSigner(alice, ""), bytes4(0x523e3260));
    }

    // =========================================================================
    // TESTE: Bytecode permanece imutável
    // =========================================================================

    /// @notice Verifica que bytecode da TBA nunca muda
    function test_bytecode_is_immutable() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tbaAddress = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        // Lê bytecode inicial
        bytes memory bytecode1 = tbaAddress.code;
        bytes32 bytecodeHash1 = keccak256(bytecode1);

        assertGt(bytecode1.length, 0, "Bytecode deve existir");

        // Executa várias operações
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        vm.deal(address(tba), 10 ether);

        vm.prank(alice);
        tba.execute(bob, 1 ether, "", 0);

        vm.prank(alice);
        tba.execute(bob, 2 ether, "", 0);

        // Transfere NFT para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // Bob executa operações
        vm.prank(bob);
        tba.execute(alice, 1 ether, "", 0);

        // Lê bytecode novamente
        bytes memory bytecode2 = tbaAddress.code;
        bytes32 bytecodeHash2 = keccak256(bytecode2);

        // ✅ Bytecode deve ser idêntico
        assertEq(bytecodeHash1, bytecodeHash2, "Bytecode deve ser imutavel");
        assertEq(bytecode1.length, bytecode2.length, "Tamanho do bytecode deve ser constante");
    }

    /// @notice Verifica estrutura do bytecode deployado
    function test_bytecode_structure() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        address tbaAddress = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

        bytes memory bytecode = tbaAddress.code;

        // ✅ Bytecode deve ter 173 bytes (45 bytes proxy + 128 bytes dados)
        assertEq(bytecode.length, 173, "Bytecode deve ter 173 bytes");

        // Verifica que dados imutáveis estão presentes
        ERC6551Account tba = ERC6551Account(payable(tbaAddress));
        (uint256 chainId, address tokenContract, uint256 readTokenId) = tba.token();

        assertEq(chainId, block.chainid);
        assertEq(tokenContract, address(heroCard));
        assertEq(readTokenId, tokenId);
    }

    // =========================================================================
    // TESTE: Owner é dinâmico (não hardcoded)
    // =========================================================================

    /// @notice Verifica que owner NÃO está hardcoded (é dinâmico via ownerOf)
    function test_owner_is_dynamic_not_hardcoded() public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");
        ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT())));

        // Alice é owner inicial
        assertEq(tba.isValidSigner(alice, ""), bytes4(0x523e3260));
        assertEq(tba.isValidSigner(bob, ""), bytes4(0));

        // Transfere NFT para Bob
        vm.prank(alice);
        heroCard.transferFrom(alice, bob, tokenId);

        // Owner muda automaticamente (não hardcoded)
        assertEq(tba.isValidSigner(alice, ""), bytes4(0), "Alice nao deve mais ser signer");
        assertEq(tba.isValidSigner(bob, ""), bytes4(0x523e3260), "Bob deve ser novo signer");

        // Transfere de volta para Alice
        vm.prank(bob);
        heroCard.transferFrom(bob, alice, tokenId);

        // Owner volta a ser Alice
        assertEq(tba.isValidSigner(alice, ""), bytes4(0x523e3260));
        assertEq(tba.isValidSigner(bob, ""), bytes4(0));
    }

    // =========================================================================
    // FUZZ: Dados imutáveis para múltiplos tokens
    // =========================================================================

    /// @notice Fuzz test verificando que cada token tem dados únicos e imutáveis
    function testFuzz_immutable_data_unique_per_token(uint8 numTokens) public {
        vm.assume(numTokens > 0 && numTokens <= 20);

        // Minta múltiplos tokens
        address[] memory owners = new address[](numTokens);
        uint256[] memory tokenIds = new uint256[](numTokens);
        address[] memory tbas = new address[](numTokens);

        for (uint256 i = 0; i < numTokens; i++) {
            owners[i] = makeAddr(string(abi.encodePacked("owner", i)));

            vm.prank(minter);
            tokenIds[i] = heroCard.mint(owners[i], "");
            tbas[i] = heroCard.getAccount(tokenIds[i], heroCard.DEFAULT_SALT());
        }

        // Verifica que cada TBA tem dados corretos e únicos
        for (uint256 i = 0; i < numTokens; i++) {
            ERC6551Account tba = ERC6551Account(payable(tbas[i]));
            (uint256 chainId, address tokenContract, uint256 readTokenId) = tba.token();

            // ✅ Dados devem corresponder ao token
            assertEq(chainId, block.chainid);
            assertEq(tokenContract, address(heroCard));
            assertEq(readTokenId, tokenIds[i]);

            // ✅ Owner deve ser correto
            assertEq(tba.isValidSigner(owners[i], ""), bytes4(0x523e3260));
        }

        // Verifica que todos os endereços são únicos
        for (uint256 i = 0; i < numTokens; i++) {
            for (uint256 j = i + 1; j < numTokens; j++) {
                assertTrue(tbas[i] != tbas[j], "TBAs devem ter enderecos unicos");
            }
        }
    }

    // =========================================================================
    // TESTE CREATE2: Mesmo salt com dados diferentes gera endereços diferentes
    // =========================================================================

    /// @notice Verifica que mesmo salt com tokenIds diferentes gera endereços diferentes
    function test_same_salt_different_tokenId_different_addresses() public {
        bytes32 salt = heroCard.DEFAULT_SALT();

        // Token 1
        vm.prank(minter);
        uint256 tokenId1 = heroCard.mint(alice, "");
        address tba1 = heroCard.getAccount(tokenId1, salt);

        // Token 2
        vm.prank(minter);
        uint256 tokenId2 = heroCard.mint(bob, "");
        address tba2 = heroCard.getAccount(tokenId2, salt);

        // ✅ Mesmo salt, mas endereços DIFERENTES (porque tokenId diferente)
        assertNotEq(tba1, tba2, "TBAs devem ter enderecos diferentes");

        // ✅ Cada uma tem seu owner correto
        ERC6551Account account1 = ERC6551Account(payable(tba1));
        ERC6551Account account2 = ERC6551Account(payable(tba2));

        assertEq(account1.isValidSigner(alice, ""), bytes4(0x523e3260));
        assertEq(account2.isValidSigner(bob, ""), bytes4(0x523e3260));
    }

    /// @notice Fuzz test: salt arbitrário não permite controle malicioso
    function testFuzz_arbitrary_salt_no_malicious_control(bytes32 salt) public {
        vm.prank(minter);
        uint256 tokenId = heroCard.mint(alice, "");

        // Atacante cria TBA com salt arbitrário
        vm.prank(attacker);
        address tba = heroCard.createAccountIfNeeded(tokenId, salt);

        // ✅ Alice ainda é o owner (determinado por ownerOf)
        ERC6551Account account = ERC6551Account(payable(tba));
        assertEq(account.isValidSigner(alice, ""), bytes4(0x523e3260));
        assertEq(account.isValidSigner(attacker, ""), bytes4(0));

        // ✅ Atacante não pode executar
        vm.prank(attacker);
        vm.expectRevert("ERC6551Account: nao autorizado");
        account.execute(attacker, 0, "", 0);
    }
}
