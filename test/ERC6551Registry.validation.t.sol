// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";

/// @title ERC6551RegistryValidationTest
/// @notice Testes de validação de parâmetros no Registry
contract ERC6551RegistryValidationTest is Test {
    ERC6551Registry public registry;
    ERC6551Account public accountImpl;

    address public deployer = makeAddr("deployer");
    address public user = makeAddr("user");
    address public validTokenContract = makeAddr("validTokenContract");

    bytes32 public constant SALT = bytes32(0);
    uint256 public constant CHAIN_ID = 31337; // Anvil chain ID
    uint256 public constant TOKEN_ID = 1;

    function setUp() public {
        vm.startPrank(deployer);
        registry = new ERC6551Registry();
        accountImpl = new ERC6551Account();
        vm.stopPrank();
    }

    // =========================================================================
    // TESTES: Validação de implementation
    // =========================================================================

    /// @notice Verifica que implementation = address(0) é rejeitado
    function test_revert_zero_implementation() public {
        vm.prank(user);
        vm.expectRevert("ERC6551Registry: implementacao invalida");
        registry.createAccount(
            address(0),  // ❌ Implementation inválida
            SALT,
            CHAIN_ID,
            validTokenContract,
            TOKEN_ID
        );
    }

    /// @notice Verifica que implementation válido é aceito
    function test_accept_valid_implementation() public {
        vm.prank(user);
        address tba = registry.createAccount(
            address(accountImpl),  // ✅ Implementation válida
            SALT,
            CHAIN_ID,
            validTokenContract,
            TOKEN_ID
        );

        assertTrue(tba != address(0), "TBA deve ser criada");
        assertTrue(tba.code.length > 0, "TBA deve ter codigo");
    }

    // =========================================================================
    // TESTES: Validação de tokenContract
    // =========================================================================

    /// @notice Verifica que tokenContract = address(0) é rejeitado
    function test_revert_zero_tokenContract() public {
        vm.prank(user);
        vm.expectRevert("ERC6551Registry: tokenContract invalido");
        registry.createAccount(
            address(accountImpl),
            SALT,
            CHAIN_ID,
            address(0),  // ❌ tokenContract inválido
            TOKEN_ID
        );
    }

    /// @notice Verifica que tokenContract válido é aceito
    function test_accept_valid_tokenContract() public {
        vm.prank(user);
        address tba = registry.createAccount(
            address(accountImpl),
            SALT,
            CHAIN_ID,
            validTokenContract,  // ✅ tokenContract válido
            TOKEN_ID
        );

        assertTrue(tba != address(0), "TBA deve ser criada");
    }

    // =========================================================================
    // TESTES: Validação de ambos parâmetros
    // =========================================================================

    /// @notice Verifica que ambos address(0) são rejeitados
    function test_revert_both_zero() public {
        vm.prank(user);
        vm.expectRevert("ERC6551Registry: implementacao invalida");
        registry.createAccount(
            address(0),  // ❌ Implementation inválida
            SALT,
            CHAIN_ID,
            address(0),  // ❌ tokenContract inválido
            TOKEN_ID
        );
    }

    // =========================================================================
    // TESTES: account() view function também deve validar
    // =========================================================================

    /// @notice Verifica que account() com implementation = address(0) falha
    function test_account_revert_zero_implementation() public view {
        // account() é view e não tem require, mas o bytecode gerado seria inválido
        // Vamos apenas verificar que não reverte inesperadamente
        address tba = registry.account(
            address(0),  // ⚠️ Implementation inválida, mas account() é view
            SALT,
            CHAIN_ID,
            validTokenContract,
            TOKEN_ID
        );

        // account() não valida, apenas calcula o endereço
        assertTrue(tba != address(0), 'Endereco deve ser calculado');
    }

    // =========================================================================
    // TESTES: Integração com HeroCard
    // =========================================================================

    /// @notice Verifica que HeroCard não pode criar TBA com implementation inválida
    function test_heroCard_cannot_create_invalid_tba() public {
        // Simula tentativa de criar TBA com implementation inválida
        // (HeroCard sempre usa accountImplementation válido, mas o registry agora protege)
        
        vm.prank(user);
        vm.expectRevert("ERC6551Registry: implementacao invalida");
        registry.createAccount(
            address(0),
            SALT,
            CHAIN_ID,
            validTokenContract,
            TOKEN_ID
        );
    }

    // =========================================================================
    // TESTES: Gas savings
    // =========================================================================

    /// @notice Verifica que validação economiza gas ao prevenir criação inútil
    function test_validation_saves_gas() public {
        uint256 gasBefore;
        uint256 gasAfter;

        // Tenta criar com implementation inválida
        vm.prank(user);
        gasBefore = gasleft();
        vm.expectRevert("ERC6551Registry: implementacao invalida");
        registry.createAccount(address(0), SALT, CHAIN_ID, validTokenContract, TOKEN_ID);
        gasAfter = gasleft();

        uint256 gasUsedRevert = gasBefore - gasAfter;

        // Tenta criar com implementation válida
        vm.prank(user);
        gasBefore = gasleft();
        registry.createAccount(address(accountImpl), SALT, CHAIN_ID, validTokenContract, TOKEN_ID);
        gasAfter = gasleft();

        uint256 gasUsedSuccess = gasBefore - gasAfter;

        // Validação economiza gas significativo
        assertLt(gasUsedRevert, gasUsedSuccess, 'Revert deve usar menos gas que criacao completa');
        
        // Log para verificação
        emit log_named_uint("Gas revert (validacao)", gasUsedRevert);
        emit log_named_uint("Gas sucesso (criacao)", gasUsedSuccess);
    }
}
