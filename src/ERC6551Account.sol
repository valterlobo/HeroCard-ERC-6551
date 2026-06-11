// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "./interfaces/IERC6551Account.sol";

/// @title ERC6551Account
/// @notice Token Bound Account (TBA) — conta inteligente vinculada a um NFT ERC-721.
///
/// @dev Implementa:
///   - IERC6551Account    : token(), state(), isValidSigner()
///   - IERC6551Executable : execute()
///   - IERC1271           : isValidSignature() (ERC-1271)
///   - ERC165             : supportsInterface()
///   - ERC721Holder       : onERC721Received()
///   - ERC1155Holder      : onERC1155Received() / onERC1155BatchReceived()
///   - ReentrancyGuard    : proteção contra reentrada em execute()
///
/// Estrutura do runtime code deployado pelo registry (173 bytes totais):
///
///   Bytes [0..9]    proxy preâmbulo EIP-1167        (10 bytes)
///   Bytes [10..29]  implementation address           (20 bytes)
///   Bytes [30..44]  proxy sufixo EIP-1167            (15 bytes)
///   Bytes [45..76]  salt (bytes32)                   (32 bytes)
///   Bytes [77..108] chainId (uint256)                (32 bytes)
///   Bytes [109..140] tokenContract (address padded)  (32 bytes)
///   Bytes [141..172] tokenId (uint256)               (32 bytes)
///
/// Para ler via assembly a partir de `bytes memory code = address(this).code`:
///   A variável `code` aponta para um slot de 32 bytes com o comprimento, seguido dos dados.
///   Offset de leitura = 0x20 (pular o length) + offset_no_runtime
///
/// ATENÇÃO: Transferir o NFT transfere o controle desta conta e de TODOS os
///          ativos nela contidos. Retire os ativos antes de transferir o NFT
///          se não quiser transferir o controle da carteira.
contract ERC6551Account is
    IERC1271,
    IERC6551Account,
    IERC6551Executable,
    ERC721Holder,
    ERC1155Holder, // ERC1155Holder herda de ERC165, que implementa IERC165
    ReentrancyGuard
{
    // =========================================================================
    // Eventos
    // =========================================================================

    /// @notice Emitido quando a TBA executa uma transação
    event TransactionExecuted(address indexed to, uint256 value, bytes data, uint8 operation);

    // =========================================================================
    // Constantes
    // =========================================================================

    /// @dev ERC-1271: magic value para assinatura válida
    bytes4 private constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;
    /// @dev ERC-1271: valor para assinatura inválida
    bytes4 private constant _ERC1271_INVALID = 0xffffffff;

    /// @dev ERC-6551: magic value para signer válido
    bytes4 private constant _ERC6551_VALID_SIGNER = 0x523e3260;

    /// @dev Tipo de operação CALL (único suportado)
    uint8 private constant OP_CALL = 0;

    // =========================================================================
    // Offsets do runtime code (bytes memory, inclui 0x20 do length slot)
    //
    // Runtime layout:
    //   [0..44]   proxy bytecode EIP-1167           45 bytes
    //   [45..76]  salt                               32 bytes  -> 0x20 + 45  = 0x4d
    //   [77..108] chainId                            32 bytes  -> 0x20 + 77  = 0x6d
    //   [109..140] tokenContract (padded to 32)      32 bytes  -> 0x20 + 109 = 0x8d
    //   [141..172] tokenId                           32 bytes  -> 0x20 + 141 = 0xad
    // =========================================================================
    uint256 private constant _OFFSET_SALT = 0x4d; // 0x20 + 45
    uint256 private constant _OFFSET_CHAIN_ID = 0x6d; // 0x20 + 77
    uint256 private constant _OFFSET_TOKEN_CONTRACT = 0x8d; // 0x20 + 109
    uint256 private constant _OFFSET_TOKEN_ID = 0xad; // 0x20 + 141

    // =========================================================================
    // Storage
    // =========================================================================

    /// @notice Nonce/state da conta — incrementado a cada execução.
    /// @dev Protege contra replay attacks e identifica o estado atual da conta.
    ///      Armazenado no storage do PROXY (não da implementação), pois a conta
    ///      é acessada via delegatecall do proxy EIP-1167.
    uint256 private _state;

    // =========================================================================
    // Receive ETH
    // =========================================================================

    /// @notice Permite que a TBA receba ETH diretamente
    receive() external payable override {}

    // =========================================================================
    // IERC6551Account
    // =========================================================================

    /// @inheritdoc IERC6551Account
    function state() external view override returns (uint256) {
        return _state;
    }

    /// @notice Retorna os dados do NFT vinculado a esta conta.
    /// @dev Lê os dados imutáveis embutidos no bytecode do proxy via codecopy/assembly.
    ///      address(this).code retorna o bytecode do PROXY (não da implementação),
    ///      pois esta função é chamada via delegatecall.
    ///
    ///      Layout do runtime code (173 bytes):
    ///        [0..44]   proxy EIP-1167   (45 bytes)
    ///        [45..76]  salt             (32 bytes)
    ///        [77..108] chainId          (32 bytes)
    ///        [109..140] tokenContract   (32 bytes, address padded)
    ///        [141..172] tokenId         (32 bytes)
    ///
    ///      `bytes memory code` em assembly:
    ///        code pointer -> word com length (32 bytes) + dados do runtime
    ///        mload(add(code, _OFFSET_CHAIN_ID)) lê 32 bytes a partir do offset correto
    /// @inheritdoc IERC6551Account
    function token() public view override returns (uint256 chainId, address tokenContract, uint256 tokenId) {
        bytes memory code = address(this).code;
        assembly {
            // Cada offset inclui 0x20 (32 bytes) para pular o length slot da bytes memory
            chainId := mload(add(code, _OFFSET_CHAIN_ID))
            // tokenContract: abi.encode preenche com zeros à esquerda (address = 20 bytes em slot de 32)
            // A máscara garante que os 12 bytes de padding zero sejam descartados
            tokenContract := and(mload(add(code, _OFFSET_TOKEN_CONTRACT)), 0xffffffffffffffffffffffffffffffffffffffff)
            tokenId := mload(add(code, _OFFSET_TOKEN_ID))
        }
    }

    /// @inheritdoc IERC6551Account
    function isValidSigner(address signer, bytes calldata) public view override returns (bytes4) {
        if (_isValidSigner(signer)) return _ERC6551_VALID_SIGNER;
        return bytes4(0);
    }

    // =========================================================================
    // IERC6551Executable
    // =========================================================================

    /// @notice Executa uma transação a partir desta TBA.
    /// @dev Apenas o proprietário atual do NFT vinculado pode chamar esta função.
    ///      Suporta apenas operação CALL (operation == 0).
    ///      Protegido contra reentrância via ReentrancyGuard.
    ///      O state é incrementado ANTES da chamada externa (checks-effects-interactions).
    ///
    /// @param to        Endereço de destino
    /// @param value     Valor ETH em wei a enviar
    /// @param data      Calldata da chamada
    /// @param operation Tipo de operação (apenas 0 = CALL suportado)
    /// @return result   Retorno da chamada executada
    /// @inheritdoc IERC6551Executable
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        override
        nonReentrant
        returns (bytes memory result)
    {
        require(_isValidSigner(msg.sender), "ERC6551Account: nao autorizado");
        require(operation == OP_CALL, "ERC6551Account: operacao nao suportada");

        // Incrementa o state ANTES da chamada (CEI pattern)
        unchecked {
            ++_state;
        }

        bool success;
        (success, result) = to.call{value: value}(data);

        if (!success) {
            // Propaga o revert com a mensagem original
            assembly {
                revert(add(result, 32), mload(result))
            }
        }

        emit TransactionExecuted(to, value, data, operation);
    }

    // =========================================================================
    // IERC1271 — Validação de Assinaturas
    // =========================================================================

    /// @notice Valida uma assinatura ERC-1271.
    /// @dev Utiliza SignatureChecker da OpenZeppelin, que suporta tanto
    ///      EOAs (ECDSA) quanto contratos inteligentes (ERC-1271 recursivo).
    ///      A assinatura é validada contra o owner atual do NFT vinculado.
    ///
    /// @param hash      Hash dos dados assinados (tipicamente EIP-712)
    /// @param signature Assinatura a validar
    /// @return magicValue `0x1626ba7e` se válida, `0xffffffff` se inválida
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        view
        override
        returns (bytes4 magicValue)
    {
        address owner = _owner();
        bool valid = SignatureChecker.isValidSignatureNow(owner, hash, signature);
        return valid ? _ERC1271_MAGIC_VALUE : _ERC1271_INVALID;
    }

    // =========================================================================
    // ERC165 — Introspection
    // =========================================================================

    /// @notice Verifica suporte a interfaces.
    /// @dev Override de ERC165 (via ERC1155Holder) e ERC1155Holder.
    ///      Não precisamos listar IERC165 explicitamente pois ERC165 já a inclui.
    function supportsInterface(bytes4 interfaceId) public view override(ERC1155Holder) returns (bool) {
        return interfaceId == type(IERC1271).interfaceId || interfaceId == type(IERC6551Account).interfaceId
            || interfaceId == type(IERC6551Executable).interfaceId || super.supportsInterface(interfaceId); // delega para ERC165 e ERC1155Holder
    }

    // =========================================================================
    // Helpers internos
    // =========================================================================

    /// @notice Retorna o proprietário atual do NFT vinculado à conta.
    /// @dev Consulta ownerOf() em tempo real — não cached em storage.
    function _owner() internal view returns (address) {
        (, address tokenContract, uint256 tokenId) = token();
        return IERC721(tokenContract).ownerOf(tokenId);
    }

    /// @notice Retorna true se o signer é o owner atual do NFT vinculado,
    ///         ou o próprio contrato do token (que já faz controle de acesso internamente).
    function _isValidSigner(address signer) internal view returns (bool) {
        if (signer == _owner()) return true;

        // Permite que o contrato do próprio token chame execute().
        // Contratos como HeroCard verificam onlyOwnerOfToken antes de delegar
        // para a TBA, portanto confiar no tokenContract é seguro.
        (, address tokenContract,) = token();
        return signer == tokenContract;
    }
}
