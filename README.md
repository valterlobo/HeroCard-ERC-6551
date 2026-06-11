# HeroCard — Sistema ERC-6551 (Token Bound Accounts)

Projeto Foundry completo implementando o padrão **ERC-6551 (Token Bound Accounts)** para criar cartões virtuais NFT (ERC-721) que possuem sua própria carteira inteligente — capaz de acumular ETH, ERC-20, ERC-721 e ERC-1155.

---

## Arquitetura

```
┌─────────────────────────────────────────────────────────────┐
│                        HeroCard (ERC-721)                   │
│                                                             │
│  mint() ──► cria TBA automaticamente via ERC6551Registry    │
│                                                             │
│  HeroCard #0 ──► TBA-0 (ERC6551Account)                     │
│  HeroCard #1 ──► TBA-1 (ERC6551Account)                     │
│  HeroCard #N ──► TBA-N (ERC6551Account)                     │
└─────────────────────────────────────────────────────────────┘
                          │
              ┌───────────▼──────────────-┐
              │   ERC6551Registry          │
              │   (CREATE2 determinístico) │
              └───────────────────────────┘
                          │
         ┌────────────────▼────────────────-┐
         │        ERC6551Account            │
         │                                  │
         │  - Recebe ETH, ERC-20, ERC-721   │
         │  - execute() para qualquer call  │
         │  - owner = ownerOf(NFT vinculado)│
         │  - isValidSigner() / ERC-1271    │
         └──────────────────────────────────┘
```

### Contratos

| Arquivo | Descrição |
|---|---|
| `src/interfaces/IERC6551Registry.sol` | Interface do registry ERC-6551 |
| `src/interfaces/IERC6551Account.sol` | Interfaces IERC6551Account e IERC6551Executable |
| `src/ERC6551Registry.sol` | Implementação do registry (CREATE2 determinístico) |
| `src/ERC6551Account.sol` | Token Bound Account — carteira vinculada ao NFT |
| `src/HeroCard.sol` | NFT ERC-721 com integração completa ERC-6551 |
| `src/mocks/MockERC20.sol` | Token ERC-20 para testes |
| `src/mocks/MockERC721.sol` | NFT ERC-721 para testes |

---

## Setup

### Pré-requisitos

- [Foundry](https://book.getfoundry.sh/getting-started/installation) instalado
- Node.js ≥ 18 (para scripts ethers.js)

### Instalação

```bash
# Clone o repositório
git clone <repo-url>
cd card-erc6551

# Instala forge-std e dependências
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# (Opcional) instala dependências Node.js para scripts
npm install
```

### Compilação

```bash
forge build
```

---

## Testes

```bash
# Roda todos os testes
forge test -vvv

# Roda testes específicos
forge test --match-test test_mint_creates_tba -vvv

# Roda com fuzz (mais iterações)
forge test --fuzz-runs 1000

# Gas report
forge test --gas-report
```

### Cobertura dos testes

| Categoria | Testes |
|---|---|
| Mint | Mint básico, eventos, criação de TBA, controle de acesso, batch |
| TBA - Endereço | Determinismo, unicidade por token, isAccountCreated |
| TBA - Dados | token() retorna chainId/contract/tokenId corretos |
| ETH | Depósito, saque, controle de acesso |
| ERC-20 | Depósito, saque |
| ERC-721 filho | Depósito, saque |
| Execute | Transferência ETH via TBA, controle de acesso |
| Transferência | Transferência do NFT transfere controle da TBA |
| Conta direta | state(), receive(), isValidSigner(), supportsInterface() |
| AccessControl | setBaseURI() com e sem permissão |
| Fuzz | Endereços únicos por token, depósito/saque ETH |

---

## Deploy

### Testnet (Sepolia)

```bash
# Configure variáveis de ambiente
export PRIVATE_KEY=0x...
export RPC_URL=https://sepolia.infura.io/v3/SEU_KEY

# Deploy completo (usa registry canônico se disponível)
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key SEU_ETHERSCAN_KEY

# Para usar o registry canônico ERC-6551 (Sepolia):
# O endereço 0x000000006551c19487814612e58FE06813775758 já está deployado
# O script detecta automaticamente e reutiliza
```

### Variáveis de ambiente do script

| Variável | Descrição | Padrão |
|---|---|---|
| `PRIVATE_KEY` | Chave privada do deployer | obrigatório |
| `REGISTRY_ADDRESS` | Endereço do registry existente | `0x000...758` (canônico) |
| `BASE_URI` | URI base para metadados | `https://api.herocard.io/metadata/` |

---

## Scripts ethers.js

```bash
# Configure .env
cat > .env << EOF
RPC_URL=https://sepolia.infura.io/v3/SEU_KEY
PRIVATE_KEY=0x...
HERO_CARD_ADDRESS=0x...
ERC6551_ACCOUNT_IMPL=0x...
EOF

# Executa o script de interação
npm run interact
```

---

## Conceitos-chave ERC-6551

### Endereço Determinístico da TBA

O endereço de cada TBA é calculado via `CREATE2` usando a combinação:

```
TBA address = CREATE2(
  salt     = bytes32(0),
  bytecode = proxy_bytecode + abi.encode(salt, chainId, tokenContract, tokenId)
)
```

Isso garante que o endereço é único e previsível para cada NFT.

### Controle Dinâmico

O owner da TBA é **sempre** o `ownerOf(tokenId)` no momento da chamada — não é gravado em storage. Isso significa:

```
Alice compra HeroCard #5
  └─► Alice controla TBA-5 e todos os ativos dentro dela

Alice vende HeroCard #5 para Bob
  └─► Bob passa a controlar TBA-5 (e todos os ativos!)
  └─► Alice perde o acesso imediatamente
```

### ⚠️ Alerta de Segurança

> **ATENÇÃO:** Transferir um HeroCard NFT transfere automaticamente o controle da TBA e de **todos os ativos** que ela contém para o novo proprietário. **Retire seus ativos da TBA antes de vender ou transferir o NFT.**

---

## Referências

- [EIP-6551 Specification](https://eips.ethereum.org/EIPS/eip-6551)
- [Tokenbound Docs](https://docs.tokenbound.org)
- [RareSkills: ERC-6551 Explicado](https://rareskills.io/post/erc-6551)
- [ERC6551 Reference Implementation](https://github.com/erc6551/reference)
- [Registry Deployments](https://docs.tokenbound.org/contracts/deployments)
- [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x/)
