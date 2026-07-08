// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./HeroCardBase.sol";

/// @title HeroCardSBT
/// @notice Contrato ERC-721 Soulbound (Não-transferível) de "Cartões Virtuais" com integração ERC-6551 (Token Bound Accounts)
///
/// @dev Cada HeroCardSBT NFT possui uma Token Bound Account (TBA) associada que funciona
///      como uma carteira inteligente capaz de armazenar ETH, ERC-20, ERC-721 e ERC-1155.
///
///      DIFERENÇA PARA O HEROCARD ORIGINAL:
///      Este contrato é um Soulbound Token (SBT), o que significa que, uma vez mintado
///      para um endereço, ele NÃO pode ser transferido NEM destruído (burn).
///      A única operação permitida é o mint (criação).
///
///      Roles:
///        DEFAULT_ADMIN_ROLE — administrador geral (pode conceder/revogar roles)
///        MINTER_ROLE        — pode mintar novos cartões
contract HeroCardSBT is HeroCardBase {
    /// @param _registry             Endereço do registry ERC-6551
    /// @param _accountImplementation Endereço da implementação ERC6551Account
    constructor(address _registry, address _accountImplementation)
        HeroCardBase(_registry, _accountImplementation, "HeroCardSBT", "HSBT")
    {}

    /// @dev Sobrescreve a função de atualização de propriedade para tornar o token Soulbound.
    ///      Apenas MINT (from == address(0)) é permitido. Transferências e burns são bloqueados.
    ///
    ///      SEGURANÇA: A versão anterior permitia burn (to == address(0)), o que criava
    ///      uma vulnerabilidade: qualquer endereço com approve/setApprovalForAll podia
    ///      destruir o SBT do owner. Um Soulbound Token deve ser intransferível E
    ///      indestrutível por terceiros.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Apenas mint é permitido — transferências e burns são bloqueados.
        // from == address(0) indica que o token está sendo criado (mint).
        // Qualquer outro cenário (transferência ou burn) é revertido.
        require(from == address(0), "HeroCardSBT: Transferencia e burn nao permitidos (Soulbound)");

        return super._update(to, tokenId, auth);
    }
}
