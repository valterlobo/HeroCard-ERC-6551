// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IERC6551Registry
/// @notice Interface do registry oficial ERC-6551
/// @dev Baseado na especificação EIP-6551 (https://eips.ethereum.org/EIPS/eip-6551)
interface IERC6551Registry {
    /// @notice Emitido quando uma nova Token Bound Account é criada
    event ERC6551AccountCreated(
        address account,
        address indexed implementation,
        bytes32 salt,
        uint256 chainId,
        address indexed tokenContract,
        uint256 indexed tokenId
    );

    /// @notice Erro quando a conta já existe
    error AccountCreationFailed();

    /// @notice Cria uma Token Bound Account para um NFT
    /// @param implementation Endereço do contrato de implementação da conta
    /// @param salt Salt para criação determinística via CREATE2
    /// @param chainId Chain ID do NFT
    /// @param tokenContract Endereço do contrato ERC-721
    /// @param tokenId ID do token NFT
    /// @return accountAddress Endereço da TBA criada
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address accountAddress);

    /// @notice Calcula o endereço determinístico de uma TBA (sem criar)
    /// @param implementation Endereço do contrato de implementação da conta
    /// @param salt Salt para criação determinística via CREATE2
    /// @param chainId Chain ID do NFT
    /// @param tokenContract Endereço do contrato ERC-721
    /// @param tokenId ID do token NFT
    /// @return accountAddress Endereço calculado da TBA
    function account(address implementation, bytes32 salt, uint256 chainId, address tokenContract, uint256 tokenId)
        external
        view
        returns (address accountAddress);
}
