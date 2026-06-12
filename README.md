# HeroCard — ERC-6551 Token Bound Accounts

Projeto **Foundry** que implementa o padrão [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) para criar cartões virtuais NFT (ERC-721) com carteira inteligente própria — capaz de acumular ETH, ERC-20, ERC-721 e ERC-1155.


@TODO
- Testar com outros nfts
- Desenvolver um SBT PARA NAO PERMITIR TRANSFERENCIA DO NFT
- Ter dados reais nos nfts (imagem, efeitos, etc)
- Ter logica de criacao de nfts
- Ter logica de premios (tokens)


---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│                     HeroCard (ERC-721)                      │
│                                                             │
│  mint() ──► cria TBA automaticamente via ERC6551Registry    │
│                                                             │
│  HeroCard #0 ──► TBA-0 (ERC6551Account)                     │
│  HeroCard #1 ──► TBA-1 (ERC6551Account)                     │
│  HeroCard #N ──► TBA-N (ERC6551Account)                     │
└─────────────────────────────────────────────────────────────┘
                          │
              ┌───────────▼───────────────┐
              │     ERC6551Registry        │
              │  (CREATE2 determinístico) │
              └───────────────────────────┘
                          │
         ┌────────────────▼────────────────┐
         │        ERC6551Account            │
         │                                  │
         │  - Recebe ETH, ERC-20, ERC-721,  │
         │    ERC-1155                       │
         │  - execute() para qualquer call  │
         │  - owner = ownerOf(NFT vinculado)│
         │  - isValidSigner() / ERC-1271    │
         └──────────────────────────────────┘
```

### Contratos

| Arquivo | Descrição |
|---|---|
| `src/interfaces/IERC6551Registry.sol` | Interface do registry ERC-6551 |
| `src/interfaces/IERC6551Account.sol` | Interfaces `IERC6551Account` e `IERC6551Executable` |
| `src/ERC6551Registry.sol` | Registry com CREATE2 determinístico |
| `src/ERC6551Account.sol` | Token Bound Account — carteira vinculada ao NFT |
| `src/HeroCard.sol` | NFT ERC-721 com integração completa ERC-6551 |
| `src/mocks/MockERC20.sol` | Token ERC-20 para testes |
| `src/mocks/MockERC721.sol` | NFT ERC-721 para testes |

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
# Executa toda a suite (99 testes)
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

| Arquivo | Testes | Foco |
|---|---|---|
| `test/HeroCard.t.sol` | 28 | Fluxos principais + fuzz |
| `test/HeroCard.branches.t.sol` | 36 | Cobertura de branches (revert paths, casos extremos) |
| `test/ERC6551Account.t.sol` | 8 | Branches da conta (autorização, assinaturas, interfaces) |
| `test/ERC6551Registry.t.sol` | 2 | Branches do registry (idempotência, falha no CREATE2) |
| `test/ERC6551Account.signature.t.sol` | 7 | Segurança de assinaturas ERC-1271 |
| `test/ERC6551Account.transfer.t.sol` | 6 | Riscos de transferência e mitigações |
| `test/ERC6551Account.initialization.t.sol` | 12 | Inicialização de proxy e CREATE2 |

### Resultado de cobertura atual

| Contrato | Linhas | Branches | Funções |
|---|---|---|---|
| `ERC6551Account.sol` | 100% | **100%** | 100% |
| `ERC6551Registry.sol` | 100% | **100%** | 100% |
| `HeroCard.sol` | 99% | **100%** | 96% |
| `MockERC20.sol` | 100% | 100% | 100% |
| `MockERC721.sol` | 100% | 100% | 100% |

> Gerado com `forge coverage`. O `script/Deploy.s.sol` é excluído por não ser executado nos testes unitários.

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

| Variável | Descrição | Obrigatório |
|---|---|---|
| `PRIVATE_KEY` | Chave privada do deployer | ✅ |
| `RPC_URL` | Endpoint RPC da rede alvo | ✅ |
| `REGISTRY_ADDRESS` | Endereço do registry existente (deixe vazio para deployar um novo) | ❌ |
| `ETHERSCAN_API_KEY` | Chave para verificação do contrato | ❌ |

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

### Roles de acesso (HeroCard)

| Role | Permissão |
|---|---|
| `DEFAULT_ADMIN_ROLE` | Conceder/revogar qualquer role |
| `MINTER_ROLE` | Mintar novos cartões (`mint`, `mintBatch`) |
| `PAUSER_ROLE` | Pausar/despausar transferências |

### ⚠️ Alerta de segurança

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
> Ver documentação completa em `SECURITY_AUDIT_TRANSFER_RISKS.md`

---

## Segurança

### Proteções Implementadas

- **Checks-Effects-Interactions (CEI):** eventos emitidos antes das chamadas externas nos depósitos; `_state` incrementado antes de `execute()` na TBA.
- **ReentrancyGuard:** todas as funções que realizam chamadas externas são protegidas (`nonReentrant`).
- **Validação de retorno:** os resultados de `execute()` nos saques são decodificados e validados.
- **Slither:** auditoria estática realizada; warnings residuais documentados com `slither-disable` justificados.

### Auditorias de Segurança

O projeto passou por **6 auditorias de segurança abrangentes**:

| Auditoria | Status | Arquivo |
|-----------|--------|---------|
| Conformidade com ERC-6551 | ✅ Conforme | README.md |
| Gas Griefing e Loops | ✅ Seguro | `SECURITY_ANALYSIS_GAS_GRIEFING.md` |
| Assinatura de Mensagens (ERC-1271) | ✅ Seguro | `SECURITY_AUDIT_SIGNATURE.md` |
| Riscos de Transferência | ⚠️ Documentado | `SECURITY_AUDIT_TRANSFER_RISKS.md` |
| Inicialização de Proxy | ✅ Seguro | `SECURITY_AUDIT_PROXY_INITIALIZATION.md` |
| CREATE2 e Colisão | ✅ Seguro | `SECURITY_AUDIT_CREATE2.md` |

**Total de Testes:** 99 ✅ (100% passed)  
**Cobertura:** 100% de branches em contratos principais  
**Vulnerabilidades Críticas:** 0

### Documentação de Segurança

- `SECURITY_SUMMARY.md` - Resumo consolidado de todas as auditorias
- `docs/GAS_GRIEFING_PATTERNS.md` - Padrões seguros para futuras implementações
- Testes de segurança em `test/ERC6551Account.*.t.sol`

---

## Referências

- [EIP-6551 Specification](https://eips.ethereum.org/EIPS/eip-6551)
- [Tokenbound Docs](https://docs.tokenbound.org)
- [ERC6551 Reference Implementation](https://github.com/erc6551/reference)
- [Registry Canônico — Deployments](https://docs.tokenbound.org/contracts/deployments)
- [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x/)
- [Foundry Book](https://book.getfoundry.sh/)
