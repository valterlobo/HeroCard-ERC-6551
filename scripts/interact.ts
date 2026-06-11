/**
 * scripts/interact.js
 * Exemplo de interação com o sistema HeroCard ERC-6551 via ethers.js v6
 *
 * Instale as dependências:
 *   npm install ethers dotenv
 *
 * Configure .env:
 *   RPC_URL=https://sepolia.infura.io/v3/SEU_KEY
 *   PRIVATE_KEY=0x...
 *   HERO_CARD_ADDRESS=0x...
 *   ERC6551_ACCOUNT_IMPL=0x...
 *   ERC6551_REGISTRY=0x...
 */

import { ethers } from "ethers";
import * as dotenv from "dotenv";
dotenv.config();

// ─────────────────────────────────────────────────────────────────────────────
// ABIs mínimas
// ─────────────────────────────────────────────────────────────────────────────

const HERO_CARD_ABI = [
  "function mint(address to, string calldata tokenURI) external returns (uint256)",
  "function getAccount(uint256 tokenId, bytes32 salt) external view returns (address)",
  "function isAccountCreated(uint256 tokenId, bytes32 salt) external view returns (bool)",
  "function createAccountIfNeeded(uint256 tokenId, bytes32 salt) external returns (address)",
  "function depositEth(uint256 tokenId) external payable",
  "function depositERC20(uint256 tokenId, address tokenContract, uint256 amount) external",
  "function depositERC721(uint256 tokenId, address nftContract, uint256 nftTokenId) external",
  "function withdrawEth(uint256 tokenId, address to, uint256 amount) external",
  "function withdrawERC20(uint256 tokenId, address to, address tokenContract, uint256 amount) external",
  "function executeOnAccount(uint256 tokenId, address to, uint256 value, bytes calldata data) external payable returns (bytes memory)",
  "function totalSupply() external view returns (uint256)",
  "function ownerOf(uint256 tokenId) external view returns (address)",
  "function DEFAULT_SALT() external view returns (bytes32)",
  "event CardMinted(address indexed to, uint256 indexed tokenId)",
  "event TbaCreated(uint256 indexed tokenId, address indexed accountAddress)",
];

const ERC6551_ACCOUNT_ABI = [
  "function token() external view returns (uint256 chainId, address tokenContract, uint256 tokenId)",
  "function state() external view returns (uint256)",
  "function isValidSigner(address signer, bytes calldata context) external view returns (bytes4)",
  "function execute(address to, uint256 value, bytes calldata data, uint8 operation) external payable returns (bytes memory)",
];

// ─────────────────────────────────────────────────────────────────────────────
// Setup
// ─────────────────────────────────────────────────────────────────────────────

const provider = new ethers.JsonRpcProvider(process.env.RPC_URL);
const signer   = new ethers.Wallet(process.env.PRIVATE_KEY!, provider);

const heroCard = new ethers.Contract(
  process.env.HERO_CARD_ADDRESS!,
  HERO_CARD_ABI,
  signer
);

const DEFAULT_SALT = ethers.ZeroHash; // bytes32(0)

// ─────────────────────────────────────────────────────────────────────────────
// Funções de exemplo
// ─────────────────────────────────────────────────────────────────────────────

/**
 * 1. Minta um novo HeroCard e obtém o endereço da TBA
 */
async function mintHeroCard(recipientAddress: string): Promise<void> {
  console.log(`\n[mint] Mintando HeroCard para ${recipientAddress}...`);

  const tx = await heroCard.mint(recipientAddress, "ipfs://QmHeroCardMetadata");
  console.log(`  tx hash: ${tx.hash}`);

  const receipt = await tx.wait();
  const mintEvent = receipt?.logs
    .map((log: any) => {
      try { return heroCard.interface.parseLog(log); } catch { return null; }
    })
    .find((e: any) => e?.name === "CardMinted");

  const tokenId: bigint = mintEvent?.args[1];
  console.log(`  tokenId mintado: ${tokenId}`);

  const tba = await heroCard.getAccount(tokenId, DEFAULT_SALT);
  console.log(`  TBA address:     ${tba}`);

  const created = await heroCard.isAccountCreated(tokenId, DEFAULT_SALT);
  console.log(`  TBA criada?      ${created}`);
}

/**
 * 2. Deposita ETH na TBA de um cartão
 */
async function depositEthToCard(tokenId: bigint, amountEth: string): Promise<void> {
  const amount = ethers.parseEther(amountEth);
  console.log(`\n[deposit] Depositando ${amountEth} ETH no cartão #${tokenId}...`);

  const tba = await heroCard.getAccount(tokenId, DEFAULT_SALT);

  const tx = await heroCard.depositEth(tokenId, { value: amount });
  await tx.wait();

  const balance = await provider.getBalance(tba);
  console.log(`  Saldo da TBA: ${ethers.formatEther(balance)} ETH`);
}

/**
 * 3. Executa uma chamada arbitrária pela TBA
 */
async function executeViaCard(
  tokenId: bigint,
  targetAddress: string,
  valueEth: string,
  calldata: string
): Promise<void> {
  const value = ethers.parseEther(valueEth);
  console.log(`\n[execute] Executando via TBA do cartão #${tokenId}...`);
  console.log(`  target:  ${targetAddress}`);
  console.log(`  value:   ${valueEth} ETH`);
  console.log(`  calldata: ${calldata}`);

  const tx = await heroCard.executeOnAccount(
    tokenId, targetAddress, value, calldata, { value }
  );
  const receipt = await tx.wait();
  console.log(`  tx hash: ${receipt?.hash}`);
}

/**
 * 4. Lê os dados de uma TBA
 */
async function readTbaInfo(tokenId: bigint): Promise<void> {
  const tba = await heroCard.getAccount(tokenId, DEFAULT_SALT);
  const tbaContract = new ethers.Contract(tba, ERC6551_ACCOUNT_ABI, provider);

  console.log(`\n[info] TBA do cartão #${tokenId}:`);
  console.log(`  Endereço: ${tba}`);

  const created = await heroCard.isAccountCreated(tokenId, DEFAULT_SALT);
  if (!created) {
    console.log("  TBA ainda não criada.");
    return;
  }

  const [chainId, tokenContract, retTokenId] = await tbaContract.token();
  const state = await tbaContract.state();
  const balance = await provider.getBalance(tba);

  console.log(`  chainId:       ${chainId}`);
  console.log(`  tokenContract: ${tokenContract}`);
  console.log(`  tokenId:       ${retTokenId}`);
  console.log(`  state/nonce:   ${state}`);
  console.log(`  ETH balance:   ${ethers.formatEther(balance)} ETH`);
}

// ─────────────────────────────────────────────────────────────────────────────
// Main
// ─────────────────────────────────────────────────────────────────────────────

async function main() {
  const network = await provider.getNetwork();
  console.log(`\n=== HeroCard ERC-6551 Interaction Script ===`);
  console.log(`Network: ${network.name} (chainId: ${network.chainId})`);
  console.log(`Signer:  ${await signer.getAddress()}`);

  const totalSupply = await heroCard.totalSupply();
  console.log(`Total HeroCards: ${totalSupply}`);

  if (totalSupply === 0n) {
    // Demonstração de mint
    await mintHeroCard(await signer.getAddress());
  }

  const tokenId = 0n; // usa o primeiro cartão

  // Exibe informações da TBA
  await readTbaInfo(tokenId);

  // Deposita 0.001 ETH
  // await depositEthToCard(tokenId, "0.001");

  // Executa transferência de ETH via TBA
  // const recipient = "0xRecipient...";
  // await executeViaCard(tokenId, recipient, "0.0005", "0x");
}

main().catch(console.error);
