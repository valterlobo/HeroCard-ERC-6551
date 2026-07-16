// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/ERC6551Registry.sol";
import "../src/interfaces/IERC6551Registry.sol";
import "../src/HeroCardAccount.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract DummyToken is ERC721 {
    constructor() ERC721("Dummy", "DUM") {}
}

contract ERC6551RegistryTest is Test {
    ERC6551Registry public registry;
    address public implementation;
    bytes32 public salt = bytes32(uint256(1));
    uint256 public chainId = 1;
    address public tokenContract;
    uint256 public tokenId = 1;

    function setUp() public {
        registry = new ERC6551Registry();
        implementation = address(new HeroCardAccount());
        tokenContract = address(new DummyToken());
    }

    // Branch 1: accountAddress.code.length > 0
    function test_createAccount_AlreadyExists() public {
        // Create first time
        address account1 = registry.createAccount(implementation, salt, chainId, tokenContract, tokenId);

        // Create second time - should hit the early return
        address account2 = registry.createAccount(implementation, salt, chainId, tokenContract, tokenId);

        assertEq(account1, account2);
    }

    // Branch 2: accountAddress == address(0)
    function test_createAccount_Create2Fails() public {
        // Pre-calculate address
        address target = registry.account(implementation, salt, chainId, tokenContract, tokenId);

        // Set nonce to 1 so CREATE2 fails
        vm.setNonce(target, 1);

        // Ensure code length is 0 so we bypass the early return
        assertEq(target.code.length, 0);

        vm.expectRevert(IERC6551Registry.AccountCreationFailed.selector);
        registry.createAccount(implementation, salt, chainId, tokenContract, tokenId);
    }

    // Branch 3: implementation == address(0)
    function test_createAccount_InvalidImplementation() public {
        vm.expectRevert("ERC6551Registry: implementacao invalida");
        registry.createAccount(address(0), salt, chainId, tokenContract, tokenId);
    }

    // Branch 4: tokenContract == address(0)
    function test_createAccount_InvalidTokenContract() public {
        vm.expectRevert("ERC6551Registry: tokenContract invalido");
        registry.createAccount(implementation, salt, chainId, address(0), tokenId);
    }

    // Branch 5: caminho feliz de criação de account
    function test_createAccount_Success() public {
        address created = registry.createAccount(implementation, salt, chainId, tokenContract, tokenId);
        address predicted = registry.account(implementation, salt, chainId, tokenContract, tokenId);

        assertEq(created, predicted);
        assertTrue(created.code.length > 0, "deve ter codigo de contrato");
    }
}
