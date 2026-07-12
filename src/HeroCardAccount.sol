// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC6551Account.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/// @title HeroCardAccount
/// @notice Subclasse de ERC6551Account específica para HeroCard.
/// @dev Extensão de `ERC6551Account` que implementa a função de 
///      meta-transações (executeWithSignature). Aderimos à especificação 
///      ERC-6551 de isolamento mantendo estritamente a validação de assinatura
///      através de EIP-1271 com o owner verdadeiro.
contract HeroCardAccount is ERC6551Account {

    /// @notice Executa uma chamada usando uma assinatura digital do proprietário atual
    /// @dev Permite meta-transactions encaminhadas pelo HeroCardBase ou outros relayers
    /// @param to Endereço de destino
    /// @param value Valor ETH em wei a enviar
    /// @param data Calldata da chamada
    /// @param operation Tipo de operação (apenas 0 = CALL suportado)
    /// @param signature Assinatura do owner sobre o payload (incluindo state como nonce)
    /// @return result Retorno da chamada executada
    function executeWithSignature(
        address to,
        uint256 value,
        bytes calldata data,
        uint8 operation,
        uint256 deadline,
        bytes calldata signature
    ) external payable nonReentrant returns (bytes memory result) {
        (uint256 chainId,,) = token();
        if (chainId != block.chainid) revert WrongChain(chainId, block.chainid);

        require(operation == 0, "ERC6551Account: operacao nao suportada");
        require(block.timestamp <= deadline, "ERC6551Account: assinatura expirada");

        // Hash incluindo o chainId atual, endereço da conta, deadline e nonce (_state)
        // para evitar cross-chain replay, cross-account replay e assinaturas expiradas
        bytes32 structHash =
            keccak256(abi.encode(block.chainid, address(this), to, value, keccak256(data), operation, deadline, _state));

        // Transforma no formato "Ethereum Signed Message"
        bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(structHash);

        require(
            SignatureChecker.isValidSignatureNow(_owner(), ethSignedHash, signature),
            "ERC6551Account: assinatura invalida"
        );

        // Proteção contra ownership cycle: TBA não pode transferir o próprio NFT
        _checkOwnershipCycle(to, data);

        // Incrementa o state ANTES da chamada (CEI pattern)
        unchecked {
            ++_state;
        }

        bool success;
        // slither-disable-next-line missing-zero-check,arbitrary-send-eth
        (success, result) = to.call{value: value}(data);

        if (!success) {
            // Propaga o revert com a mensagem original
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit TransactionExecuted(to, value, data, operation);
    }
}
