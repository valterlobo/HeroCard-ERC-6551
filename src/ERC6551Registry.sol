// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IERC6551Registry.sol";

/// @title ERC6551Registry
/// @notice Implementação do registry ERC-6551 para criação de Token Bound Accounts via CREATE2.
///
/// @dev Baseado na implementação de referência: https://github.com/erc6551/reference
///
///      O registry canônico está deployado em:
///        0x000000006551c19487814612e58FE06813775758
///      Use este contrato apenas em redes onde o registry oficial não estiver disponível.
///
///      Estrutura do initcode gerado por _creationCode (183 bytes):
///
///        [0..9]    deployer EIP-1167 (10 bytes)
///                  3d 60 ad 80 60 0a 3d 39 81 f3
///                  Faz CODECOPY de [10..182] para mem[0], então RETURN 173 bytes.
///
///        [10..54]  proxy EIP-1167 runtime (45 bytes)
///                  363d3d373d3d3d363d73 + <impl 20 bytes> + 5af43d82803e903d91602b57fd5bf3
///
///        [55..86]  salt   (bytes32, 32 bytes)
///        [87..118] chainId (uint256, 32 bytes)
///        [119..150] tokenContract (address padded to 32 bytes)
///        [151..182] tokenId (uint256, 32 bytes)
///
///      O CREATE2 deploya o resultado da execução do initcode, ou seja, os bytes [10..182]:
///
///        Runtime code (173 bytes = 0xad):
///          [0..44]   proxy EIP-1167           (45 bytes)
///          [45..76]  salt                     (32 bytes)
///          [77..108] chainId                  (32 bytes)
///          [109..140] tokenContract (padded)  (32 bytes)
///          [141..172] tokenId                 (32 bytes)
contract ERC6551Registry is IERC6551Registry {

    // =========================================================================
    // IERC6551Registry
    // =========================================================================

    /// @inheritdoc IERC6551Registry
    /// @dev Idempotente: se a conta já existe (tem código), retorna o endereço sem revert.
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address accountAddress) {
        bytes memory code = _creationCode(implementation, chainId, tokenContract, tokenId, salt);

        accountAddress = Create2Lib.computeAddress(salt, keccak256(code));

        // Idempotente: se já existe código, retorna sem erro
        if (accountAddress.code.length > 0) return accountAddress;

        assembly {
            accountAddress := create2(0, add(code, 0x20), mload(code), salt)
        }

        if (accountAddress == address(0)) revert AccountCreationFailed();

        emit ERC6551AccountCreated(
            accountAddress, implementation, salt, chainId, tokenContract, tokenId
        );
    }

    /// @inheritdoc IERC6551Registry
    /// @dev Puramente view — não altera estado. Pode ser chamado antes do deploy.
    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external view returns (address) {
        bytes32 bytecodeHash =
            keccak256(_creationCode(implementation, chainId, tokenContract, tokenId, salt));
        return Create2Lib.computeAddress(salt, bytecodeHash);
    }

    // =========================================================================
    // Geração do initcode
    // =========================================================================

    /// @notice Gera o initcode (183 bytes) que o CREATE2 executa para deployar a TBA.
    ///
    /// @dev Estrutura do initcode:
    ///   - Bytes [0..9]:   deployer de 10 bytes que faz CODECOPY+RETURN dos próximos 173 bytes
    ///   - Bytes [10..44]: proxy runtime EIP-1167 (preâmbulo + impl + sufixo)
    ///   - Bytes [45+]:    abi.encode(salt, chainId, tokenContract, tokenId) — dados imutáveis
    ///
    ///   O resultado do CREATE2 é o runtime code: proxy(45) + dados(128) = 173 bytes.
    ///   A função token() na implementação lê esses dados via address(this).code.
    function _creationCode(
        address implementation,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId,
        bytes32 salt
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            // Deployer (10 bytes): RETURNDATASIZE PUSH1(0xad) DUP1 PUSH1(0x0a) RETURNDATASIZE CODECOPY DUP2 RETURN
            hex"3d60ad80600a3d3981f3",
            // Proxy EIP-1167 runtime (45 bytes):
            //   preâmbulo (10): 363d3d373d3d3d363d73
            //   implementation (20 bytes)
            //   sufixo (15): 5af43d82803e903d91602b57fd5bf3
            hex"363d3d373d3d3d363d73",
            implementation,
            hex"5af43d82803e903d91602b57fd5bf3",
            // Dados imutáveis (128 bytes): lidos por token() via codecopy
            // Ordem: salt, chainId, tokenContract, tokenId
            // Runtime offsets: [45..76], [77..108], [109..140], [141..172]
            abi.encode(salt, chainId, tokenContract, tokenId)
        );
    }
}

// =============================================================================
// Biblioteca auxiliar CREATE2
// =============================================================================

/// @title Create2Lib
/// @notice Calcula endereços CREATE2 determinísticos.
/// @dev Renomeada de Create2 para evitar colisão com @openzeppelin/contracts/utils/Create2.sol
///      caso ambas sejam importadas no mesmo arquivo de teste.
library Create2Lib {
    /// @notice Calcula o endereço CREATE2 usando address(this) como deployer.
    function computeAddress(bytes32 salt, bytes32 bytecodeHash)
        internal
        view
        returns (address)
    {
        return computeAddress(salt, bytecodeHash, address(this));
    }

    /// @notice Calcula o endereço CREATE2 com deployer explícito.
    /// @dev Implementa: keccak256(0xff ++ deployer ++ salt ++ bytecodeHash)[12:]
    function computeAddress(bytes32 salt, bytes32 bytecodeHash, address deployer)
        internal
        pure
        returns (address addr)
    {
        assembly {
            // Usa scratch space (0x00..0x3f) para montar os 85 bytes:
            //   [0]:      0xff
            //   [1..20]:  deployer (20 bytes)
            //   [21..52]: salt (32 bytes)
            //   [53..84]: bytecodeHash (32 bytes)
            let ptr := mload(0x40)
            mstore8(ptr, 0xff)
            mstore(add(ptr, 0x01), shl(0x60, deployer)) // coloca deployer nos 20 bytes altos
            mstore(add(ptr, 0x15), salt)                 // salt nos bytes [21..52]
            mstore(add(ptr, 0x35), bytecodeHash)         // hash nos bytes [53..84]
            addr := and(
                keccak256(ptr, 0x55),                    // hash de 85 bytes
                0xffffffffffffffffffffffffffffffffffffffff // máscara para 20 bytes de address
            )
        }
    }
}
