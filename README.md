# HeroCard — ERC-6551 Token Bound Accounts

Projeto **Foundry** que implementa o padrão [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) para criar cartões virtuais NFT (ERC-721) com carteira inteligente própria — capaz de acumular ETH, ERC-20, ERC-721 e ERC-1155.

Disponível em duas variantes:
- **`HeroCard`** — NFT transferível padrão.
- **`HeroCardSBT`** — variante Soulbound (intransferível); apenas mint e burn são permitidos, eliminando o risco de transferência acidental de controle da TBA.

@TODO
- Testar com outros nfts
- Ter dados reais nos nfts (imagem, efeitos, etc)
- Ter logica de criacao de nfts
- Ter logica de premios (tokens)
- Usar o registry canônico ERC-6551 por padrão (atualmente o projeto deploya seu próprio registry)

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│              HeroCard / HeroCardSBT (ERC-721)               │
│                                                             │
│  mint() ──► cria TBA automaticamente via ERC6551Registry    │
│                                                             │
│  Card #0 ──► TBA-0 (ERC6551Account)                         │
│  Card #1 ──► TBA-1 (ERC6551Account)                         │
│  Card #N ──► TBA-N (ERC6551Account)                         │
└─────────────────────────────────────────────────────────────┘
                          │
              ┌───────────▼───────────────┐
              │     ERC6551Registry       │
              │  (CREATE2 determinístico) │
              └───────────────────────────┘
                          │
         ┌────────────────▼────────────────┐
         │        ERC6551Account            │
         │                                  │
         │  - Recebe ETH, ERC-20, ERC-721,  │
         │    ERC-1155                      │
         │  - execute() / executeBatch()    │
         │    para chamadas CALL            │
         │  - owner = ownerOf(NFT vinculado)│
         │  - isValidSigner() / ERC-1271    │
         │  - protegida contra ownership    │
         │    cycle (não transfere o        │
         │    próprio NFT vinculado)        │
         └──────────────────────────────────┘
```

### Contratos

| Arquivo                               | Descrição                                           |
| ------------------------------------- | --------------------------------------------------- |
| `src/interfaces/IERC6551Registry.sol` | Interface do registry ERC-6551                      |
| `src/interfaces/IERC6551Account.sol`  | Interfaces `IERC6551Account` e `IERC6551Executable` |
| `src/ERC6551Registry.sol`             | Registry com CREATE2 determinístico                 |
| `src/ERC6551Account.sol`              | Token Bound Account — carteira vinculada ao NFT     |
| `src/HeroCardBase.sol`                | Contrato ERC-721 abstrato com toda a lógica de integração ERC-6551 |
| `src/HeroCard.sol`                    | NFT ERC-721 transferível (extende `HeroCardBase`)   |
| `src/HeroCardSBT.sol`                 | NFT ERC-721 Soulbound — intransferível (extende `HeroCardBase`) |
| `src/mocks/MockERC20.sol`             | Token ERC-20 para testes                            |
| `src/mocks/MockERC721.sol`            | NFT ERC-721 para testes                             |

---

## Setup

### Pré-requisitos

- [Foundry](https://book.getfoundry.sh/getting-started/installation) instalado
- Node.js ≥ 18 (apenas para o script `scripts/interact.ts`)

### Instalação

```bash
git clone <repo-url>
cd card-erc6551

# Dependências Solidity
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# (Opcional) dependências Node.js para script de interação
npm install
```

### Compilação

```bash
forge build
```

---

## Testes

```bash
# Executa toda a suite (155 testes)
forge test

# Com output detalhado
forge test -vvv

# Teste específico
forge test --match-test test_mint_creates_tba -vvv

# Fuzz com mais iterações
forge test --fuzz-runs 1000

# Relatório de gas
forge test --gas-report

# Cobertura de código
forge coverage
```

### Suite de testes

| Arquivo                                      | Testes | Foco                                                          |
| --------------------------------------------- | ------ | --------------------------------------------------------------- |
| `test/HeroCard.t.sol`                        | 28     | Fluxos principais + fuzz                                        |
| `test/HeroCard.branches.t.sol`               | 41     | Cobertura de branches (revert paths, casos extremos)             |
| `test/HeroCard.coverage.t.sol`               | 5      | `unpause`, revogação de aprovações ERC-20/ERC-721                |
| `test/HeroCardSBT.t.sol`                     | 5      | Mint, transferência bloqueada, TBA em token soulbound             |
| `test/ERC6551Account.t.sol`                  | 9      | Branches da conta (autorização, assinaturas, interfaces)         |
| `test/ERC6551Account.signature.t.sol`        | 7      | Segurança de assinaturas ERC-1271                                 |
| `test/ERC6551Account.transfer.t.sol`         | 6      | Riscos de transferência e mitigações                              |
| `test/ERC6551Account.initialization.t.sol`   | 12     | Inicialização de proxy e CREATE2                                  |
| `test/ERC6551Account.delegatecall.t.sol`     | 9      | CALL vs DELEGATECALL/CREATE, isolamento de storage, selfdestruct  |
| `test/ERC6551Account.nonce.t.sol`            | 9      | `state()` / proteção contra replay, persistência, overflow        |
| `test/ERC6551Account.reentrancy_access.t.sol`| 14     | Reentrância, controle de acesso, mudança de owner                 |
| `test/ERC6551Registry.t.sol`                 | 2      | Branches do registry (idempotência, falha no CREATE2)             |
| `test/ERC6551Registry.validation.t.sol`      | 8      | Validação de parâmetros críticos (`implementation`, `tokenContract`) |

> ⚠️ **Lacuna de cobertura conhecida:** `executeBatch()` e a proteção contra ownership cycle (`OwnershipCycleDetected`) foram adicionados a `ERC6551Account.sol` mas ainda não possuem testes dedicados. Contribuições nessa área são bem-vindas — ver seção [Segurança](#segurança) abaixo para o que precisa ser coberto.

### Resultado de cobertura atual

| Contrato              | Linhas | Branches | Funções |
| --------------------- | ------ | -------- | ------- |
| `ERC6551Account.sol`  | 100%   | **100%** | 100%    |
| `ERC6551Registry.sol` | 100%   | **100%** | 100%    |
| `HeroCard.sol`        | 99%    | **100%** | 96%     |
| `MockERC20.sol`       | 100%   | 100%     | 100%    |
| `MockERC721.sol`      | 100%   | 100%     | 100%    |

> Gerado com `forge coverage`. O `script/Deploy.s.sol` é excluído por não ser executado nos testes unitários. As métricas acima foram coletadas antes da adição de `executeBatch()` e `_checkOwnershipCycle()` — recomenda-se reexecutar `forge coverage` após a cobertura desses caminhos ser adicionada.

---

## Analise Estatica

```bash
slither . --exclude-informational --filter-paths "lib/" --solc-args "--base-path . --include-path lib"
```

---

## Deploy

### Variáveis de ambiente

Copie `.env.example` e preencha:

```bash
cp .env.example .env
```

| Variável            | Descrição                                                          | Obrigatório |
| ------------------- | ------------------------------------------------------------------ | ----------- |
| `PRIVATE_KEY`       | Chave privada do deployer                                          | ✅           |
| `RPC_URL`           | Endpoint RPC da rede alvo                                          | ✅           |
| `REGISTRY_ADDRESS`  | Endereço do registry existente (deixe vazio para deployar um novo) | ❌           |
| `ETHERSCAN_API_KEY` | Chave para verificação do contrato                                 | ❌           |

### Testnet (Sepolia)

```bash
source .env

forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

> O registry canônico ERC-6551 (`0x000000006551c19487814612e58FE06813775758`) já está deployado na Sepolia. O script o detecta automaticamente e o reutiliza quando disponível.

---

## Script de interação (ethers.js)

```bash
# Configure o .env com os endereços pós-deploy
RPC_URL=https://sepolia.infura.io/v3/SEU_KEY
PRIVATE_KEY=0x...
HERO_CARD_ADDRESS=0x...
ERC6551_ACCOUNT_IMPL=0x...

# Executa
npm run interact
```

---

## Conceitos-chave ERC-6551

### Endereço determinístico da TBA

O endereço de cada TBA é calculado via `CREATE2`:

```
TBA address = CREATE2(
  deployer = ERC6551Registry,
  salt     = bytes32(0),       ← DEFAULT_SALT
  bytecode = proxy_EIP1167 + abi.encode(salt, chainId, tokenContract, tokenId)
)
```

Isso garante que o endereço é **único e previsível** para cada NFT, mesmo antes do deploy.

### Controle dinâmico

O owner da TBA é **sempre** o `ownerOf(tokenId)` avaliado no momento da chamada — não é armazenado em storage. Isso significa:

```
Alice compra HeroCard #5
  └─► Alice controla TBA-5 e todos os ativos dentro dela

Alice vende HeroCard #5 para Bob
  └─► Bob passa a controlar TBA-5 (incluindo todos os ativos!)
  └─► Alice perde o acesso imediatamente
```

Se esse comportamento não for desejado para o seu caso de uso, use `HeroCardSBT` — a variante soulbound impede a transferência do NFT (e, por consequência, do controle da TBA) após o mint.

### Execução em lote (`executeBatch`)

Além de `execute()` (uma chamada por vez), a TBA suporta `executeBatch()` para executar múltiplas chamadas atomicamente — se qualquer uma falhar, todo o lote é revertido:

```solidity
tba.executeBatch(
  [tokenA, tokenB],          // targets
  [0, 0],                    // values
  [approveCalldata, transferCalldata], // data
  0                           // operation (apenas CALL é suportado)
);
```

`executeBatch` é uma extensão deste projeto — não faz parte da interface `IERC6551Executable` oficial da EIP-6551, que define apenas `execute()`.

### Proteção contra ownership cycle

A TBA **não pode transferir o próprio NFT ao qual está vinculada** via `execute()`/`executeBatch()`. Uma tentativa de chamar `transferFrom`/`safeTransferFrom` no `tokenContract` movendo o `tokenId` vinculado reverte com `OwnershipCycleDetected()`. Isso evita que a TBA fique presa controlando a si mesma (estado em que nenhuma conta consegue mais autorizar execuções).

> Esta proteção cobre apenas o ciclo direto (TBA transferindo seu próprio NFT-mãe). Ciclos indiretos entre múltiplas TBAs (TBA-A possui NFT-B, cuja TBA-B possui NFT-A) não são detectados — esse é um risco inerente ao padrão ERC-6551, reconhecido na própria especificação como não totalmente solucionável on-chain.

### Roles de acesso (HeroCard / HeroCardSBT)

| Role                 | Permissão                               |
| --------------------- | ---------------------------------------- |
| `DEFAULT_ADMIN_ROLE`  | Conceder/revogar qualquer role           |
| `MINTER_ROLE`         | Mintar novos cartões (`mint`, `mintBatch`) |
| `PAUSER_ROLE`         | Pausar/despausar transferências           |

### ⚠️ Alerta de segurança (HeroCard transferível)

> **ATENÇÃO:** Transferir um HeroCard NFT transfere automaticamente o controle da TBA e de **todos os ativos** que ela contém para o novo proprietário.
>
> **ANTES DE TRANSFERIR O NFT:**
> 1. ✅ Saque TODOS os ativos (ETH, ERC-20, ERC-721, ERC-1155)
> 2. ✅ Revogue TODAS as aprovações ERC-20 concedidas pela TBA
> 3. ✅ Revogue TODOS os operadores ERC-721/1155 aprovados
> 4. ✅ Feche TODAS as posições DeFi (staking, lending, etc)
>
> **Riscos se não fizer isso:**
> - 🔴 Aprovações ERC-20 persistem após transferência (novo owner pode ter tokens drenados)
> - 🔴 Operadores ERC-721/1155 persistem (novo owner pode ter NFTs roubados)
> - 🟡 Posições DeFi são herdadas pelo novo owner
>
> Se a transferência de controle da TBA nunca é desejada, use `HeroCardSBT` em vez de `HeroCard`.

---

## Segurança

### Proteções implementadas

- **Checks-Effects-Interactions (CEI):** eventos emitidos antes das chamadas externas nos depósitos; `_state` incrementado antes de `execute()`/`executeBatch()` na TBA.
- **ReentrancyGuard:** todas as funções que realizam chamadas externas são protegidas (`nonReentrant`).
- **Validação de retorno:** os resultados de `execute()` nos saques são decodificados e validados.
- **Restrição a CALL:** `execute()`/`executeBatch()` aceitam apenas `operation == 0`; DELEGATECALL/CREATE/CREATE2 são rejeitados.
- **Proteção contra ownership cycle:** a TBA não pode transferir o próprio NFT vinculado (ver seção acima). ⚠️ *Aguardando testes dedicados — ver [Testes](#testes).*
- **Soulbound (opcional):** `HeroCardSBT` elimina por completo o risco de transferência de controle da TBA.

### Pontos em aberto

| Item | Situação |
|---|---|
| Cobertura de teste para `executeBatch()` | ❌ Pendente |
| Cobertura de teste para `OwnershipCycleDetected` | ❌ Pendente |
| Uso do registry canônico ERC-6551 por padrão | ❌ Pendente — projeto deploya registry próprio; ver `@TODO` |
| Ciclos indiretos entre múltiplas TBAs | ℹ️ Fora do escopo desta implementação (risco reconhecido pela própria EIP-6551) |

### Análise estática

O projeto roda Slither (`slither . --exclude-informational ...`) como parte do fluxo de revisão. Nenhum relatório de auditoria formal está versionado no repositório no momento — recomenda-se gerar e versionar a saída do Slither e de uma eventual revisão manual antes de qualquer deploy em mainnet.

**Total de testes:** 155 ✅  
**Cobertura declarada:** 100% de linhas/branches nos contratos `ERC6551Account.sol` e `ERC6551Registry.sol` (medida antes da adição de `executeBatch`/ownership-cycle — recomenda-se remedir)  
**Vulnerabilidades críticas conhecidas:** nenhuma identificada na revisão atual

---

## Referências

- [EIP-6551 Specification](https://eips.ethereum.org/EIPS/eip-6551)
- [Tokenbound Docs](https://docs.tokenbound.org)
- [ERC6551 Reference Implementation](https://github.com/erc6551/reference)
- [Registry Canônico — Deployments](https://docs.tokenbound.org/contracts/deployments)
- [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x/)
- [Foundry Book](https://book.getfoundry.sh/)
- [Transformando NFTs em Carteiras Inteligentes: ERC-6551 e Token Bound Accounts (TBAs)](https://dev.to/valterlobo/transformando-nfts-em-carteiras-inteligentes-erc-6551-e-token-bound-accounts-tbas-h1p) — artigo introdutório (dev.to)
