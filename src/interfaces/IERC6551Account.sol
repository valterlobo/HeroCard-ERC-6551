// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title IERC6551Account
/// @notice Interface padrão para Token Bound Accounts (EIP-6551)
interface IERC6551Account {
    /// @notice Recebe ETH sem dados
    receive() external payable;

    /// @notice Retorna o nonce atual da conta (para replay protection)
    function state() external view returns (uint256);

    /// @notice Retorna os dados do token vinculado à conta
    /// @return chainId   Chain ID da rede do NFT
    /// @return tokenContract Endereço do contrato ERC-721
    /// @return tokenId   ID do token NFT
    function token() external view returns (uint256 chainId, address tokenContract, uint256 tokenId);

    /// @notice Verifica se um endereço é o signatário válido para esta conta
    /// @param signer    Endereço a ser verificado
    /// @param context   Dados de contexto adicionais
    /// @return magicValue Retorna `0x523e3260` se válido
    function isValidSigner(address signer, bytes calldata context) external view returns (bytes4 magicValue);
}

/// @title IERC6551Executable
/// @notice Interface de execução para Token Bound Accounts
interface IERC6551Executable {
    /// @notice Executa uma operação a partir da TBA
    /// @param to        Endereço de destino
    /// @param value     Valor ETH a enviar (em wei)
    /// @param data      Dados calldata da chamada
    /// @param operation Tipo de operação (0 = CALL, 1 = DELEGATECALL, 2 = CREATE)
    /// @return result   Retorno da chamada executada
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        returns (bytes memory result);
}
