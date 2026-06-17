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
///
/// SEGURANÇA: Esta implementação previne ownership cycles — a TBA não pode
///            transferir o próprio NFT ao qual está vinculada via execute().
contract ERC6551Account is
    IERC1271,
    IERC6551Account,
    IERC6551Executable,
    ERC721Holder,
    ERC1155Holder, // ERC1155Holder herda de ERC165, que implementa IERC165
    ReentrancyGuard
{
    // =========================================================================
    // Erros
    // =========================================================================

    /// @notice Emitido quando a TBA tenta transferir o próprio NFT vinculado via execute()
    /// @dev Previne ownership cycles: TBA → NFT → TBA (controle circular)
    error OwnershipCycleDetected();

    // =========================================================================
    // Eventos
    // =========================================================================

    /// @notice Emitido quando a TBA executa uma transação
    event TransactionExecuted(address indexed to, uint256 value, bytes data, uint8 operation);

    /// @notice Emitido quando a TBA executa um batch de transações
    event BatchExecuted(uint256 count, uint256 operation);

    // =========================================================================
    // Constantes
    // =========================================================================

    /// @dev ERC-1271: magic value para assinatura válida.
    ///      Calculado como: bytes4(keccak256("isValidSignature(bytes32,bytes)"))
    bytes4 private constant _ERC1271_MAGIC_VALUE = 0x1626ba7e;

    /// @dev ERC-1271: valor retornado quando a assinatura é INVÁLIDA.
    ///
    ///      ESCOLHA DELIBERADA: mantemos 0xffffffff em vez de bytes4(0).
    ///
    ///      Motivo — ambiguidade do bytes4(0):
    ///        Quando uma chamada externa falha, reverte ou o contrato não implementa
    ///        a função, o ABI decoder pode interpretar o retorno como 0x00000000.
    ///        Retornar bytes4(0) como "inválido" tornaria impossível distinguir
    ///        entre "assinatura verificada e rejeitada" e "chamada falhou".
    ///
    ///      Conformidade com o ecossistema:
    ///        OpenZeppelin SignatureChecker, Gnosis Safe e a maioria das carteiras
    ///        smart contract usam 0xffffffff como valor de falha explícito.
    ///        Usar o mesmo valor maximiza a interoperabilidade.
    ///
    ///      Referência: EIP-1271 não especifica um valor de falha obrigatório,
    ///        apenas exige que seja diferente de 0x1626ba7e. O valor 0xffffffff
    ///        tornou-se o padrão de facto da indústria.
    bytes4 private constant _ERC1271_INVALID = 0xffffffff;

    /// @dev ERC-6551: magic value para signer válido
    bytes4 private constant _ERC6551_VALID_SIGNER = 0x523e3260;

    /// @dev Tipo de operação CALL (único suportado)
    uint8 private constant OP_CALL = 0;

    // ── Selectors ERC-721 monitorados para detecção de ownership cycle ──────
    /// @dev transferFrom(address,address,uint256)
    bytes4 private constant _TRANSFER_FROM = IERC721.transferFrom.selector;
    /// @dev safeTransferFrom(address,address,uint256)
    bytes4 private constant _SAFE_TRANSFER_FROM_3 = bytes4(keccak256("safeTransferFrom(address,address,uint256)"));
    /// @dev safeTransferFrom(address,address,uint256,bytes)
    bytes4 private constant _SAFE_TRANSFER_FROM_4 = bytes4(keccak256("safeTransferFrom(address,address,uint256,bytes)"));

    /// @dev Tamanho mínimo de calldata para conter selector (4) + from (32) + to (32) + tokenId (32)
    uint256 private constant _MIN_TRANSFER_DATA = 4 + 32 + 32 + 32;

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

    /// @notice Verifica se um endereço é um signer válido para esta TBA.
    /// @dev Implementa IERC6551Account.isValidSigner() conforme ERC-6551.
    ///
    ///      Parâmetro `context`:
    ///        A especificação ERC-6551 inclui `context` para permitir lógica de
    ///        autorização adicional além da simples verificação de ownership do NFT.
    ///        Exemplos de uso avançado (implementáveis via override de
    ///        `_isValidSignerWithContext`):
    ///
    ///          • Permissões delegadas — context codifica uma assinatura do owner
    ///            autorizando um endereço terceiro a agir temporariamente;
    ///          • Acesso com prazo — context contém um timestamp de expiração;
    ///          • Operação específica — context especifica quais funções o signer
    ///            está autorizado a chamar (RBAC fino);
    ///          • Prova de Merkle — context contém uma prova que o signer pertence
    ///            a um conjunto pré-aprovado.
    ///
    ///      Nesta implementação base o `context` é aceito mas não utilizado:
    ///        A autorização é determinada exclusivamente por:
    ///          1. `signer == ownerOf(boundNFT)` — owner atual do NFT vinculado;
    ///          2. `signer == tokenContract` — o contrato HeroCard (que já
    ///             valida onlyOwnerOfToken antes de delegar para a TBA).
    ///
    ///        Subclasses podem sobrescrever `_isValidSignerWithContext` para
    ///        implementar lógica baseada no conteúdo do `context`.
    ///
    /// @param signer  Endereço a verificar
    /// @param context Dados adicionais de contexto (ignorado nesta implementação base;
    ///                disponível para override em subclasses)
    /// @return        `0x523e3260` se autorizado, `bytes4(0)` se não autorizado
    /// @inheritdoc IERC6551Account
    function isValidSigner(address signer, bytes calldata context) public view override returns (bytes4) {
        if (_isValidSigner(signer) || _isValidSignerWithContext(signer, context)) {
            return _ERC6551_VALID_SIGNER;
        }
        return bytes4(0);
    }

    /// @notice Hook de extensão para autorização baseada em context.
    /// @dev Ponto de override para subclasses que desejam implementar lógica
    ///      de autorização adicional usando o parâmetro `context` do ERC-6551.
    ///
    ///      Esta implementação base sempre retorna `false` — sem lógica de context.
    ///      Subclasses devem sobrescrever este método ao invés de `isValidSigner`
    ///      para preservar o comportamento base de verificação de owner/tokenContract.
    ///
    ///      Exemplo de uso:
    ///      ```solidity
    ///      function _isValidSignerWithContext(
    ///          address signer,
    ///          bytes calldata context
    ///      ) internal view virtual override returns (bool) {
    ///          if (context.length == 0) return false;
    ///          // Decodifica contexto: (delegado, expiry, assinatura do owner)
    ///          (address delegated, uint256 expiry, bytes memory ownerSig) =
    ///              abi.decode(context, (address, uint256, bytes));
    ///          if (signer != delegated) return false;
    ///          if (block.timestamp > expiry) return false;
    ///          bytes32 digest = keccak256(abi.encode(delegated, expiry));
    ///          return SignatureChecker.isValidSignatureNow(_owner(), digest, ownerSig);
    ///      }
    ///      ```
    ///
    /// @param signer  Endereço a verificar
    /// @param context Dados adicionais passados pelo caller
    /// @return        true se o signer é autorizado via contexto; false caso contrário
    // solhint-disable-next-line no-unused-vars
    function _isValidSignerWithContext(address signer, bytes calldata context)
        internal
        view
        virtual
        returns (bool)
    {
        // Suprimir warnings de parâmetros não utilizados na implementação base
        signer;
        context;
        return false;
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

        // Proteção contra ownership cycle: TBA não pode transferir o próprio NFT
        _checkOwnershipCycle(to, data);

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

    /// @notice Executa múltiplas transações em batch a partir desta TBA.
    /// @dev Apenas o proprietário atual do NFT vinculado pode chamar esta função.
    ///      Suporta apenas operação CALL (operation == 0).
    ///      Protegido contra reentrância via ReentrancyGuard.
    ///      O state é incrementado ANTES das chamadas externas (CEI pattern).
    ///      Se qualquer chamada falhar, toda a transação é revertida (atomicidade).
    ///      Os arrays `targets`, `values` e `data` devem ter o mesmo comprimento.
    ///
    /// @param targets   Array de endereços de destino
    /// @param values    Array de valores ETH em wei a enviar por chamada
    /// @param data      Array de calldata por chamada
    /// @param operation Tipo de operação (apenas 0 = CALL suportado)
    /// @return results  Array com os retornos de cada chamada executada
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data,
        uint256 operation
    ) external payable nonReentrant returns (bytes[] memory results) {
        require(_isValidSigner(msg.sender), "ERC6551Account: nao autorizado");
        require(operation == OP_CALL, "ERC6551Account: operacao nao suportada");

        uint256 length = targets.length;
        require(length > 0, "ERC6551Account: batch vazio");
        require(values.length == length && data.length == length, "ERC6551Account: arrays com tamanhos diferentes");

        // Incrementa o state ANTES das chamadas (CEI pattern)
        unchecked {
            ++_state;
        }

        results = new bytes[](length);

        for (uint256 i = 0; i < length;) {
            // Proteção contra ownership cycle em cada chamada do batch
            _checkOwnershipCycle(targets[i], data[i]);

            bool success;
            (success, results[i]) = targets[i].call{value: values[i]}(data[i]);

            if (!success) {
                // Propaga o revert com a mensagem original da chamada que falhou
                bytes memory revertData = results[i];
                assembly {
                    revert(add(revertData, 32), mload(revertData))
                }
            }

            unchecked {
                ++i;
            }
        }

        emit BatchExecuted(length, operation);
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
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();

        // ✅ Adicionar verificação de chainId conforme especificação oficial
        if (chainId != block.chainid) return address(0);

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

    /// @notice Previne que a TBA transfira o NFT ao qual está vinculada.
    /// @dev Um ownership cycle ocorre quando a TBA tenta executar uma transferência
    ///      do próprio NFT que controla esta conta — isso tornaria a TBA proprietária
    ///      de si mesma, criando um estado em que ninguém pode autorizar execuções.
    ///
    ///      Detecta as três variantes de transferência ERC-721:
    ///        - transferFrom(from, to, tokenId)
    ///        - safeTransferFrom(from, to, tokenId)
    ///        - safeTransferFrom(from, to, tokenId, data)
    ///
    ///      Layout ABI das três funções (após o selector de 4 bytes):
    ///        word 0 (bytes 4..35)  : from  (address, padded)
    ///        word 1 (bytes 36..67) : to    (address, padded)
    ///        word 2 (bytes 68..99) : tokenId (uint256)
    ///
    /// @param to   Endereço de destino da chamada em execute()
    /// @param data Calldata da chamada em execute()
    function _checkOwnershipCycle(address to, bytes calldata data) internal view {
        // Otimização: só interessa quando o destino é o tokenContract
        (, address tokenContract, uint256 boundTokenId) = token();
        if (to != tokenContract) return;

        // Calldata mínima: 4 bytes selector + 3 words ABI (from, to, tokenId)
        if (data.length < _MIN_TRANSFER_DATA) return;

        // Verifica se é uma das três variantes de transferência ERC-721
        bytes4 selector = bytes4(data[:4]);
        if (
            selector != _TRANSFER_FROM && selector != _SAFE_TRANSFER_FROM_3
                && selector != _SAFE_TRANSFER_FROM_4
        ) return;

        // Extrai o tokenId (terceiro argumento ABI = bytes 68..99 do calldata)
        // offset: 4 (selector) + 32 (from) + 32 (to) = 68
        uint256 transferredTokenId = abi.decode(data[4 + 32 + 32:4 + 32 + 32 + 32], (uint256));

        if (transferredTokenId == boundTokenId) {
            revert OwnershipCycleDetected();
        }
    }
}
