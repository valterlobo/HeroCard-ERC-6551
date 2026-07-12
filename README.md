# HeroCard — ERC-6551 Token Bound Accounts

Projeto **Foundry** que implementa o padrão [ERC-6551](https://eips.ethereum.org/EIPS/eip-6551) para criar cartões virtuais NFT (ERC-721) com carteira inteligente própria — capaz de acumular ETH, ERC-20, ERC-721 e ERC-1155.

Disponível em duas variantes:
- **`HeroCard`** — NFT transferível padrão.
- **`HeroCardSBT`** — Variante Soulbound (intransferível); apenas mint e burn são permitidos, eliminando o risco de transferência acidental de controle da TBA.

## 🚀 Novidades e Melhorias Recentes
- **Suporte a `executeBatch`**: As contas Token Bound agora podem executar dezenas de transações de forma atômica (se uma falhar, todas são revertidas).
- **Proteção contra Ownership Cycles**: Prevenção total para que a TBA não transfira o próprio NFT-mãe, evitando travamentos irreversíveis de controle.
- **Segurança 100% Testada**: Os contratos essenciais `ERC6551Account` e `ERC6551Registry` atingiram a marca de **100% de cobertura de código**, incluindo cobertura de branches, garantindo o rigor na validação de permissões e EIP-1271.

## 🚧 Roadmap / TODO
- [ ] Testar integração do registry com outras coleções NFT existentes.
- [ ] Integrar metadados reais, atributos dinâmicos e imagens ricas nos NFTs.
- [ ] Desenvolver frontend/dApp em React/Next.js para visualização simplificada do inventário das TBAs.
- [ ] Refatorar a criação das TBAs para referenciar o registry canônico ERC-6551 (`0x000000006551c19487814612e58FE06813775758`) por padrão nas redes que o suportam.

---

## 🏗 Arquitetura

```text
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
         │        ERC6551Account           │
         │                                 │
         │  - Recebe ETH, ERC-20, ERC-721, │
         │    ERC-1155                     │
         │  - execute() / executeBatch()   │
         │  - owner = ownerOf(NFT)         │
         │  - isValidSigner() (ERC-1271)   │
         │  - Sem Ownership Cycles         │
         └─────────────────────────────────┘
```

### Contratos Principais

| Arquivo | Descrição |
| --- | --- |
| `ERC6551Registry.sol` | Registry com `CREATE2` determinístico para previsibilidade do endereço das carteiras. |
| `ERC6551Account.sol` | Implementação da carteira inteligente vinculada (Token Bound Account). |
| `HeroCardBase.sol` | Contrato ERC-721 base abstrato que consolida toda a integração TBA e rotinas comuns. |
| `HeroCard.sol` | Implementação final do NFT transferível. |
| `HeroCardSBT.sol` | Implementação final do NFT Soulbound (intransferível). |

---

## 💻 Setup e Instalação

**Pré-requisitos**:
- [Foundry](https://book.getfoundry.sh/getting-started/installation) instalado e atualizado.

```bash
git clone <repo-url>
cd card-erc6551

# Instala dependências do Foundry
forge install foundry-rs/forge-std --no-commit
forge install OpenZeppelin/openzeppelin-contracts --no-commit

# Compila o projeto
forge build
```

---

## 🧪 Testes e Cobertura

O projeto conta com mais de **180 testes unitários** e de integração exaustivos, organizados em 15 suítes modulares para garantir cobertura máxima de todas as edge-cases.

```bash
# Roda todos os testes
forge test

# Roda com trace detalhado
forge test -vvv

# Gera relatório de gas
forge test --gas-report

# Roda relatório de cobertura
forge coverage
```

### Métricas de Cobertura de Código

Após as últimas atualizações de segurança e implementação dos testes exaustivos sobre o `executeBatch` e proteções estruturais, os resultados atualizados comprovam a robustez do core:

| Contrato | Linhas | Branches | Funções |
| --- | --- | --- | --- |
| `ERC6551Account.sol` | **100%** | **100%** | **100%** |
| `ERC6551Registry.sol` | **100%** | **100%** | **100%** |
| `HeroCardSBT.sol` | **100%** | **100%** | **100%** |
| `HeroCard.sol` | **100%** | **100%** | **100%** |
| `HeroCardBase.sol` | 98.7% | 100% | 95.8% |

> Todas as mitigacões de Reentrância, Falhas de Signatures (EIP-1271) e Riscos de Transferência (Tokens e Aprovações pendentes) estão mapeadas nos testes!

---

## 🚀 Deploy em Testnet (Sepolia)

Configure seu `.env` a partir do modelo `.env.example`:

```bash
cp .env.example .env
# Adicione suas variáveis RPC_URL, PRIVATE_KEY e ETHERSCAN_API_KEY
```

Script de Deploy usando o Foundry:
```bash
source .env
forge script script/Deploy.s.sol --rpc-url $RPC_URL --broadcast --verify --etherscan-api-key $ETHERSCAN_API_KEY
```

---

## 🛡 Segurança e Conceitos Importantes

### 1. Dinâmica de Transferência (Atenção redobrada)
O dono da carteira TBA é SEMPRE o titular do NFT atrelado, `ownerOf(tokenId)`. Portanto, se você possuir um **`HeroCard`** (versão transferível) e vender ou transferir esse NFT para outra carteira, **a TBA e todos os ativos acumulados nela irão magicamente para o novo dono!**
- 🛑 **Atenção**: Sempre se certifique de sacar fundos (ETH, ERC-20, NFTs) ou revogar aprovações de gasto da carteira inteligente antes de transferir o `HeroCard`.
- Para projetos nos quais não deseja correr o risco do usuário perder os próprios fundos, adote a versão atrelada à alma: **`HeroCardSBT`**.

### 2. Endereço Determinístico (CREATE2)
O endereço público da TBA para cada ID de NFT do `HeroCard` é previsível (através da instrução `CREATE2`). Isso permite que os jogadores e sistemas depositem fundos/itens em uma carteira "fantasma" que ainda não foi concretizada na blockchain. Assim que a primeira ação que exige estado (como o Deploy ou Minting) ocorrer, a TBA é gerada debaixo do capô.

### 3. Bloqueio de Ownership Cycles
Para evitar um bloqueio lógico do contrato ("TBA ser proprietária do próprio NFT HeroCard atrelado a ela"), o método de envio foi projetado para negar tentativas intrínsecas de transferir seu próprio NFT. O `ERC6551Account` mapeia localmente as chamadas para `transferFrom` e `safeTransferFrom` garantindo segurança.

### 4. Fluxo de assinatura e condições de execução das TBAs
Para integradores, o fluxo de execução das TBAs segue as regras abaixo:

1. A TBA só é válida no chain em que foi criada originalmente. Se o `chainId` embutido no bytecode da TBA não coincidir com `block.chainid`, a execução é rejeitada.
2. O signer autorizado é o dono atual do NFT vinculado ao tokenId. A validação é feita por `isValidSigner()` e pela assinatura no payload.
3. A assinatura é calculada sobre um hash estruturado contendo:
   - `block.chainid`
   - `address(this)` (o endereço da TBA)
   - `to`
   - `value`
   - `keccak256(data)`
   - `operation`
   - `deadline`
   - `state` (nonce interno da TBA)
4. O payload deve ser assinado com o formato Ethereum Signed Message (`EthSignedMessage`), e o valor de `deadline` deve estar no futuro para que a assinatura seja aceita.
5. As operações suportadas pela TBA são apenas `CALL` (`operation = 0`). `DELEGATECALL` e `CREATE` são rejeitados.
6. O estado `_state` é incrementado antes da execução para evitar replay de assinatura para a mesma TBA.
7. O contrato bloqueia tentativas de criar ownership cycles, incluindo transferências diretas e aprovações de `boundTokenId` que possam levar o NFT vinculado para dentro da própria TBA.

#### Exemplo de payload para integradores
```solidity
bytes32 structHash = keccak256(
    abi.encode(
        block.chainid,
        tbaAddress,
        to,
        value,
        keccak256(data),
        uint8(0),
        deadline,
        state
    )
);

bytes32 ethSignedHash = MessageHashUtils.toEthSignedMessageHash(structHash);
```

#### Regras práticas para quem integra
- Sempre use a TBA correta para o tokenId do HeroCard correspondente.
- Nunca reutilize uma assinatura após o `deadline` expirar.
- Não confie apenas no `to` do payload; valide o conteúdo do `data` e o valor `value` antes de relatar a transação.
- Para operações financeiras, considere um fluxo de relayer com validação adicional de destino e limite de valor.
- Em integrações front-end, prefira exibir o `deadline`, o `state` e o `to` da execução para o usuário antes de confirmar.

---

## 📚 Referências

- [EIP-6551: Non-fungible Token Bound Accounts](https://eips.ethereum.org/EIPS/eip-6551)
- [Reference Implementation Github](https://github.com/erc6551/reference)
- [OpenZeppelin ERC-721](https://docs.openzeppelin.com/contracts/5.x/erc721)
- [Artigo Introdutório no Dev.to (Valter Lobo)](https://dev.to/valterlobo/transformando-nfts-em-carteiras-inteligentes-erc-6551-e-token-bound-accounts-tbas-h1p)
