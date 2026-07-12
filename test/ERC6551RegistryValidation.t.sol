// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/HeroCardAccount.sol";

contract ERC6551RegistryValidationTest is Test {
    function testSupportsERC1271() public {
        address validImpl = address(new HeroCardAccount());
        (bool success, bytes memory data) = validImpl.staticcall(abi.encodeWithSelector(0x01ffc9a7, bytes4(0x1626ba7e)));
        assertTrue(success);
        assertTrue(abi.decode(data, (bool)));
    }
}
