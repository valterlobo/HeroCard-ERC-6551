// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC6551Account.sol";

/// @title HeroCardAccount
/// @notice Subclasse de ERC6551Account específica para HeroCard.
/// @dev Adiciona o contrato do token como signer válido para permitir
///      a delegação de chamadas (ex: withdrawEth, executeOnAccount)
///      a partir do próprio contrato HeroCard.
contract HeroCardAccount is ERC6551Account {
    // A verificação signer == tokenContract foi removida para
    // aderir estritamente à especificação ERC-6551 e evitar
    // a quebra do princípio de isolamento da TBA.
}
