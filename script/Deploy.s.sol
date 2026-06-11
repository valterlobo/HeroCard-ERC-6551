// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {Script, console} from "forge-std/Script.sol";

import "../src/ERC6551Registry.sol";
import "../src/ERC6551Account.sol";
import "../src/HeroCard.sol";

/// @title DeployHeroCard
/// @notice Script de deploy completo do sistema ERC-6551 HeroCard
///
/// Uso com Foundry:
///   forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast --verify
///
/// Variáveis de ambiente:
///   PRIVATE_KEY      — chave privada do deployer
///   REGISTRY_ADDRESS — (opcional) endereço do registry já deployado na rede
///   BASE_URI         — URI base para metadados (ex: https://api.herocard.io/metadata/)
contract DeployHeroCard is Script {
    // Endereço canônico do registry ERC-6551 (mainnet, Sepolia, etc.)
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        // Lê o endereço do registry do ambiente (fallback para canônico)
        address registryAddr = vm.envOr("REGISTRY_ADDRESS", CANONICAL_REGISTRY);

        string memory baseUri = vm.envOr("BASE_URI", string("https://api.herocard.io/metadata/"));

        console.log("=== Deploy HeroCard ERC-6551 ===");
        console.log("Deployer:    ", deployer);
        console.log("Registry:    ", registryAddr);
        console.log("Base URI:    ", baseUri);
        console.log("Chain ID:    ", block.chainid);

        vm.startBroadcast(deployerKey);

        // ─────────────────────────────────────────────────────────────────────
        // 1. Deploy ou reutiliza o Registry ERC-6551
        // ─────────────────────────────────────────────────────────────────────
        ERC6551Registry registry;

        if (registryAddr.code.length == 0) {
            console.log("\n[1/3] Registry canonico nao encontrado. Fazendo deploy local...");
            registry = new ERC6551Registry();
            console.log("      Registry deployado em:", address(registry));
        } else {
            console.log("\n[1/3] Reutilizando registry existente:", registryAddr);
            registry = ERC6551Registry(registryAddr);
        }

        // ─────────────────────────────────────────────────────────────────────
        // 2. Deploy da implementação da conta ERC-6551
        // ─────────────────────────────────────────────────────────────────────
        console.log("\n[2/3] Deploy da ERC6551Account (implementacao)...");
        ERC6551Account accountImpl = new ERC6551Account();
        console.log("      ERC6551Account deployada em:", address(accountImpl));

        // ─────────────────────────────────────────────────────────────────────
        // 3. Deploy do HeroCard NFT
        // ─────────────────────────────────────────────────────────────────────
        console.log("\n[3/3] Deploy do HeroCard ERC-721...");
        HeroCard heroCard = new HeroCard(address(registry), address(accountImpl));
        console.log("HeroCard deployado em:", address(heroCard));

        // ─────────────────────────────────────────────────────────────────────
        // 4. Demo: Minta um cartão e cria sua TBA
        // ─────────────────────────────────────────────────────────────────────
        console.log("\n=== Demo: Mintando HeroCard #0 ===");

        uint256 tokenId = heroCard.mint(deployer, "ipfs://QmHeroCard0");
        console.log("HeroCard mintado - tokenId:", tokenId);
        console.log("  Dono:                      ", deployer);

        address tba = heroCard.getAccount(tokenId, heroCard.DEFAULT_SALT());
        console.log("  TBA (Token Bound Account): ", tba);
        console.log("  TBA criada?               ", heroCard.isAccountCreated(tokenId, heroCard.DEFAULT_SALT()));

        // ─────────────────────────────────────────────────────────────────────
        // 5. Demo: Deposita 0.01 ETH na TBA
        // ─────────────────────────────────────────────────────────────────────
        if (deployer.balance >= 0.01 ether) {
            console.log("\n=== Demo: Depositando 0.01 ETH na TBA ===");
            heroCard.depositEth{value: 0.01 ether}(tokenId);
            console.log("  Saldo da TBA (wei):", tba.balance);
        }

        vm.stopBroadcast();

        // ─────────────────────────────────────────────────────────────────────
        // Resumo final
        // ─────────────────────────────────────────────────────────────────────
        console.log("\n=== Resumo do Deploy ===");
        console.log("ERC6551Registry:    ", address(registry));
        console.log("ERC6551Account impl:", address(accountImpl));
        console.log("HeroCard NFT:       ", address(heroCard));
        console.log("TBA do tokenId 0:   ", tba);
    }
}
