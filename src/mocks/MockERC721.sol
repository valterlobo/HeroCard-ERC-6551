// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @notice Token ERC-721 simples para testes (simula um NFT filho)
contract MockERC721 is ERC721 {
    uint256 private _nextId;

    constructor(string memory name, string memory symbol) ERC721(name, symbol) {}

    function mint(address to) external returns (uint256 tokenId) {
        tokenId = _nextId++;
        _safeMint(to, tokenId);
    }
}
