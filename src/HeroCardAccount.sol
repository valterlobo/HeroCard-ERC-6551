// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./ERC6551Account.sol";

/// @title HeroCardAccount
/// @notice Subclasse de ERC6551Account específica para HeroCard.
/// @dev Adiciona o contrato do token como signer válido para permitir 
///      a delegação de chamadas (ex: withdrawEth, executeOnAccount) 
///      a partir do próprio contrato HeroCard.
contract HeroCardAccount is ERC6551Account {
    /// @notice Retorna true se o signer é o owner atual do NFT vinculado,
    ///         ou o próprio contrato do token.
    function _isValidSigner(address signer) internal view override returns (bool) {
        if (super._isValidSigner(signer)) return true;

        // Permite que o contrato do próprio token chame execute().
        // Contratos como HeroCard verificam onlyOwnerOfToken antes de delegar
        // para a TBA, portanto confiar no tokenContract é seguro neste contexto.
        (, address tokenContract,) = token();
        return signer == tokenContract;
    }
}
