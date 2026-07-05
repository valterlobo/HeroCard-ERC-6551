// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./HeroCardBase.sol";

/// @title HeroCard
/// @notice Contrato ERC-721 de "Cartões Virtuais" com integração ERC-6551 (Token Bound Accounts)
///
/// @dev Cada HeroCard NFT possui uma Token Bound Account (TBA) associada que funciona
///      como uma carteira inteligente capaz de armazenar ETH, ERC-20, ERC-721 e ERC-1155.
///
///      ATENÇÃO IMPORTANTE:
///      - Transferir um HeroCard transfere AUTOMATICAMENTE o controle da TBA
///        e de TODOS os ativos que ela contém para o novo proprietário.
///      - Retire os ativos da TBA antes de transferir o NFT caso não queira
///        transferir o controle da carteira junto.
///
///      Roles:
///        DEFAULT_ADMIN_ROLE — administrador geral (pode conceder/revogar roles)
///        MINTER_ROLE        — pode mintar novos cartões
contract HeroCard is HeroCardBase {
    /// @param _registry             Endereço do registry ERC-6551
    /// @param _accountImplementation Endereço da implementação ERC6551Account
    constructor(address _registry, address _accountImplementation)
        HeroCardBase(_registry, _accountImplementation, "HeroCard", "HERO")
    {}
}
