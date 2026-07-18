# HeroCard — Token Bound Accounts (ERC-6551)

> NFTs com carteira inteligente integrada. Cada cartão é um ERC-721 com uma conta própria capaz de receber e movimentar ETH, ERC-20, ERC-721 e ERC-1155.

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org)
[![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-v5-green)](https://openzeppelin.com/contracts)
[![ERC-6551](https://img.shields.io/badge/EIP-6551-orange)](https://eips.ethereum.org/EIPS/eip-6551)
[![Foundry](https://img.shields.io/badge/Foundry-latest-red)](https://book.getfoundry.sh)
[![Testes](https://img.shields.io/badge/testes-254-brightgreen)](#testes)

---

## O que é o HeroCard?

O padrão [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) permite que qualquer NFT tenha uma **Token Bound Account (TBA)** — um contrato inteligente determinístico vinculado ao token. Quem possui o NFT controla a conta; transferir o NFT transfere automaticamente o controle de tudo que está dentro dela.

O HeroCard implementa esse padrão em duas variantes:

| Contrato | Tipo | Transferência |
|---|---|---|
| `HeroCard` | NFT padrão ERC-721 | ✅ Transferível |
| `HeroCardSBT` | Soulbound Token | ❌ Intransferível e indestrutível |

---

## Arquitetura

```
┌──────────────────────────────────────────────────┐
│           HeroCard / HeroCardSBT (ERC-721)       │
│                                                  │
│  mint(to, tokenId, uri)                          │
│    └─► cria TBA automaticamente via Registry     │
│                                                  │
│  Card #1  ──►  TBA-1  (HeroCardAccount)          │
│  Card #2  ──►  TBA-2  (HeroCardAccount)          │
│  Card #N  ──►  TBA-N  (HeroCardAccount)          │
└──────────────────────────────────────────────────┘
                      │
         ┌────────────▼────────────┐
         │     ERC6551Registry     │
         │   CREATE2 determinístico│
         │   compatível com o      │
         │   registry canônico     │
         │  0x000000006551c194...  │
         └────────────┬────────────┘
                      │
         ┌────────────▼────────────┐
         │     HeroCardAccount     │
         │                         │
         │  execute()              │  ← chamada direta pelo owner
         │  executeBatch()         │  ← até 50 operações atômicas
         │  executeWithSignature() │  ← meta-transação com deadline
         │  isValidSignature()     │  ← ERC-1271
         │  token()                │  ← retorna chainId, NFT, tokenId
         │                         │
         │  owner = ownerOf(NFT)   │
         └─────────────────────────┘
```

### Contratos

| Arquivo | Responsabilidade |
|---|---|
| `ERC6551Registry.sol` | Deploya TBAs via CREATE2. Compatível com o registry canônico oficial. |
| `ERC6551Account.sol` | Lógica base da TBA: `execute`, `executeBatch`, proteção ownership cycle, ERC-1271. |
| `HeroCardAccount.sol` | Subclasse de `ERC6551Account` com suporte a meta-transações (`executeWithSignature`). |
| `HeroCardBase.sol` | Contrato NFT abstrato com depósitos, saques, allowlist e gestão de TBA. |
| `HeroCard.sol` | NFT transferível. Herda `HeroCardBase`. |
| `HeroCardSBT.sol` | NFT Soulbound. Somente mint; transferência e burn bloqueados. |

---

## Instalação

**Pré-requisito:** [Foundry](https://book.getfoundry.sh/getting-started/installation)

```bash
git clone https://github.com/valterlobo/HeroCard-ERC-6551.git
cd HeroCard-ERC-6551

# Instala dependências
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Compila
forge build
```

---

## Testes

254 testes em 17 suítes, cobrindo funcionalidade, segurança, branches e fuzzing.

```bash
# Todos os testes
forge test

# Com trace detalhado
forge test -vvv

# Relatório de gas
forge test --gas-report

# Cobertura de código
forge coverage
```

| Suíte | Testes | Área |
|---|:---:|---|
| `HeroCardBase.coverage.t.sol` | 47 | Saques, depósitos, allowlist, deadline, eventos |
| `HeroCard.branches.t.sol` | 42 | Todos os branches de `HeroCardBase` |
| `HeroCard.t.sol` | 34 | Fluxo completo: mint → TBA → depósito → saque |
| `ERC6551Account.ownershipcycle.t.sol` | 18 | Ownership cycle: transfer, approve, setApprovalForAll + fuzz |
| `ERC6551Account.branches.t.sol` | 18 | `executeBatch`: saldo, atomicidade, limite, fuzz |
| `ERC6551Account.reentrancy_access.t.sol` | 14 | Reentrância, `msg.sender` vs `tx.origin` |
| `ERC6551Account.initialization.t.sol` | 12 | Proxy imutável, bytecode, frontrunning |
| `HeroCardAccount.coverage.t.sol` | 10 | `executeWithSignature`, deadline, replay |
| `HeroCardSBT.t.sol` | 8 | Soulbound: burn por owner/operador/global bloqueado |
| Outros (9 suítes) | 51 | Nonce, delegatecall, assinatura, registry, cobertura |

---

## Deploy

Configure as variáveis de ambiente:

```bash
cp .env.example .env
# Preencha: PRIVATE_KEY, RPC_URL, ETHERSCAN_API_KEY
# Opcional: REGISTRY_ADDRESS (padrão: registry canônico ERC-6551)
```

Execute o deploy:

```bash
source .env
forge script script/Deploy.s.sol \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --etherscan-api-key $ETHERSCAN_API_KEY
```

O script detecta automaticamente se o registry canônico (`0x000000006551c19487814612e58FE06813775758`) está disponível na rede e o reutiliza. Se não estiver, faz deploy de um registry local compatível.

**Saída esperada:**

```
=== Deploy HeroCard ERC-6551 ===
[1/3] Reutilizando registry existente: 0x000000006551c19487814612e58FE06813775758
[2/3] Deploy da HeroCardAccount...
[3/3] Deploy do HeroCard ERC-721...

=== Resumo do Deploy ===
ERC6551Registry:     0x000000006551c19487814612e58FE06813775758
HeroCardAccount impl: 0xAbCd...
HeroCard NFT:        0x1234...
TBA do tokenId 1:    0x5678...
```

---

## Como usar

### 1. Mintar um cartão

```solidity
// Mint único
heroCard.mint(destinatario, tokenId, "ipfs://QmMetadata");

// Mint em lote (máximo 50)
uint256[] memory ids = new uint256[](3);
string[] memory uris = new string[](3);
ids[0] = 1; ids[1] = 2; ids[2] = 3;
uris[0] = "ipfs://Qm1"; uris[1] = "ipfs://Qm2"; uris[2] = "ipfs://Qm3";
heroCard.mintBatch(destinatario, ids, uris);
```

A TBA é criada automaticamente no mint via `_createTba`.

### 2. Consultar a TBA

```solidity
// Endereço da TBA (determinístico, pode ser consultado antes do deploy)
address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());

// Verificar se a TBA foi deployada
bool criada = heroCard.isAccountCreated(tokenId, heroCard.DEFAULT_SALT());

// Criar a TBA se por algum motivo não foi criada no mint
heroCard.createAccountIfNeeded(tokenId, heroCard.DEFAULT_SALT());
```

### 3. Depositar ativos na TBA

```solidity
// ETH
heroCard.depositEth{value: 1 ether}(tokenId);

// ERC-20 (requer approve prévio)
token.approve(address(heroCard), amount);
heroCard.depositERC20(tokenId, address(token), amount);

// ERC-721 (requer approve prévio)
nft.approve(address(heroCard), nftId);
heroCard.depositERC721(tokenId, address(nft), nftId);

// ERC-1155 (requer setApprovalForAll prévio)
token1155.setApprovalForAll(address(heroCard), true);
heroCard.depositERC1155(tokenId, address(token1155), assetId, amount);
```

> A TBA deve existir antes de depositar. Use `createAccountIfNeeded` se necessário.

### 4. Sacar ativos (meta-transação)

Os saques usam `executeWithSignature` — o owner assina o payload e qualquer relayer pode submeter:

```solidity
// 1. Montar o hash estruturado (off-chain, no frontend ou relayer)
bytes32 structHash = keccak256(abi.encode(
    block.chainid,
    tbaAddress,   // endereço da TBA, não do HeroCard
    to,
    value,
    keccak256(data),
    uint8(0),     // operation: 0 = CALL
    deadline,
    state         // nonce atual da TBA (chamar ERC6551Account.state())
));
bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", structHash));
bytes memory signature = owner.sign(ethHash);

// 2. Submeter (qualquer relayer pode chamar)
heroCard.withdrawEth(tokenId, destinatario, amount, deadline, signature);
heroCard.withdrawERC20(tokenId, address(token), destinatario, amount, deadline, signature);
heroCard.withdrawERC721(tokenId, address(nft), destinatario, nftId, deadline, signature);
heroCard.withdrawERC1155(tokenId, address(token1155), destinatario, assetId, amount, deadline, data, signature);
```

### 5. Chamar a TBA diretamente

```solidity
// O owner chama execute() diretamente na TBA
ERC6551Account tba = ERC6551Account(payable(heroCard.getAccount(tokenId, DEFAULT_SALT)));

// Chamada simples
tba.execute(enderecoDestino, valorEth, calldata, 0);

// Batch atômico (até 50 operações; se uma falhar, todas revertem)
address[] memory targets = new address[](2);
uint256[] memory values  = new uint256[](2);
bytes[]   memory data    = new bytes[](2);
uint8[]   memory ops     = new uint8[](2);
// ... preencher arrays ...
tba.executeBatch(targets, values, data, ops);
```

### 6. Revogar aprovações pendentes

```solidity
// Revogar approve de ERC-20
heroCard.revokeERC20Approvals(tokenId, address(token), spender, deadline, signature);

// Revogar setApprovalForAll de ERC-721/1155
heroCard.revokeERC721Operators(tokenId, address(nft), operator, deadline, signature);
```

---

## Segurança

### ⚠️ Transferência de HeroCard transfere tudo dentro da TBA

O owner da TBA é sempre o `ownerOf(tokenId)`. Ao transferir um `HeroCard`:
- O controle de toda a TBA passa para o novo dono
- ETH, tokens e NFTs dentro da TBA vão junto

**Sempre saque os ativos antes de vender ou transferir o NFT.**

Para evitar esse risco por design, use `HeroCardSBT` — o token não pode ser transferido.

### Proteções implementadas

**Ownership cycle:** a TBA não pode transferir o próprio NFT que a controla. A proteção cobre três vetores:
- `transferFrom` e `safeTransferFrom` (bloqueio direto)
- `approve(spender, boundTokenId)` — bloqueia aprovação do próprio tokenId
- `setApprovalForAll(operator, true)` — bloqueia habilitação global

**Replay de assinatura:** o hash inclui `chainId`, endereço da TBA, `deadline` e `_state` (nonce). Uma assinatura não pode ser reutilizada em outra chain, em outra TBA, após o deadline ou após já ter sido usada.

**Reentrância:** todas as funções externas de `HeroCardBase` e `HeroCardAccount` usam `nonReentrant`.

**Allowlist de destinos (opcional):** o admin pode ativar `enforceAllowlist` para restringir os endereços para os quais saques e execuções podem ser enviados.

```solidity
// Admin ativa a allowlist
heroCard.setEnforceAllowlist(true);

// Admin autoriza um destino específico
heroCard.setAllowedTarget(enderecoPermitido, true);
```

**Operações suportadas pela TBA:** apenas `CALL` (`operation = 0`). `DELEGATECALL` e `CREATE` são rejeitados.

**Compatibilidade de chain:** a TBA só opera na chain em que foi criada. Se `chainId` embutido no bytecode divergir de `block.chainid`, todas as operações revertem com `WrongChain`.

### HeroCardSBT — Soulbound Token

O `HeroCardSBT` sobrescreve `_update` para bloquear qualquer movimento exceto mint:

```solidity
require(from == address(0), "HeroCardSBT: Transferencia e burn nao permitidos (Soulbound)");
```

Isso inclui burn — um operador aprovado não pode destruir o SBT do dono.

---

## Registry e endereços determinísticos

O endereço da TBA é calculado deterministicamente pelo CREATE2 e pode ser conhecido antes do deploy:

```solidity
address tba = heroCard.getAccount(tokenId, DEFAULT_SALT);
// tba é o mesmo endereço que o registry canônico retornaria
// para os mesmos parâmetros (implementation, salt, chainId, tokenContract, tokenId)
```

O registry do HeroCard usa `salt` diretamente no CREATE2 — **sem derivação adicional** — garantindo que os endereços gerados sejam idênticos aos do registry canônico oficial (`0x000000006551c19487814612e58FE06813775758`). Ferramentas como o Tokenbound SDK e explorers compatíveis com ERC-6551 calculam o mesmo endereço.

> O registry canônico é usado em produção sempre que estiver disponível na rede (mainnet, Sepolia, etc.). O registry local é um fallback para redes onde o canônico ainda não foi deployado.

---

## Referências

- [EIP-6551 — Token Bound Accounts](https://eips.ethereum.org/EIPS/eip-6551)
- [erc6551/reference — implementação oficial](https://github.com/erc6551/reference)
- [Tokenbound SDK e documentação](https://docs.tokenbound.org)
- [OpenZeppelin Contracts v5](https://docs.openzeppelin.com/contracts/5.x)
- [Foundry Book](https://book.getfoundry.sh)
- [Artigo introdutório (Valter Lobo — dev.to)](https://dev.to/valterlobo/transformando-nfts-em-carteiras-inteligentes-erc-6551-e-token-bound-accounts-tbas-h1p)
