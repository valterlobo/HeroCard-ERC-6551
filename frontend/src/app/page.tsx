"use client";

import { useState, useEffect } from "react";
import { ethers } from "ethers";
import { Wallet, Plus, Send, RefreshCw, Layers, ArrowDownToLine, ArrowUpFromLine, Coins, Copy, Check } from "lucide-react";
import HeroCardABI from "@/lib/HeroCardABI.json";
import { motion, AnimatePresence } from "framer-motion";

// Endereço do contrato deployado na rede Sepolia
const CONTRACT_ADDRESS = "0x165D7525dd40ec6b6A4cAa6f266b69Ee45CF5523";

// Sub-componente para gerenciar o estado individual de cada carta
function CardItem({ id, contract, account, provider, onActionComplete }: { id: string, contract: ethers.Contract, account: string, provider: ethers.BrowserProvider, onActionComplete: () => void }) {
  const [activeTab, setActiveTab] = useState<"nft" | "eth" | "erc20">("nft");
  const [targetAddress, setTargetAddress] = useState("");
  const [amount, setAmount] = useState("");
  const [tokenAddress, setTokenAddress] = useState("");
  const [loading, setLoading] = useState(false);
  const [tbaAddress, setTbaAddress] = useState<string | null>(null);
  const [ethBalance, setEthBalance] = useState<string>("0");
  const [copied, setCopied] = useState(false);
  const [tokenBalance, setTokenBalance] = useState<string | null>(null);

  const copyToClipboard = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  useEffect(() => {
    // Buscar o endereço da TBA
    const fetchTba = async () => {
      try {
        const salt = ethers.ZeroHash;
        const address = await contract.getAccount(id, salt);
        setTbaAddress(address);
        const balance = await provider.getBalance(address);
        setEthBalance(ethers.formatEther(balance));
      } catch (e) {
        console.error("Erro ao buscar TBA", e);
      }
    };
    fetchTba();
  }, [id, contract, provider]);

  useEffect(() => {
    const fetchTokenBalance = async () => {
      if (activeTab === "erc20" && tbaAddress && ethers.isAddress(tokenAddress)) {
        try {
          const erc20Abi = [
            "function balanceOf(address) view returns (uint256)",
            "function decimals() view returns (uint8)"
          ];
          const erc20Contract = new ethers.Contract(tokenAddress, erc20Abi, provider);
          
          // Tenta buscar as casas decimais (fallback para 18 se falhar)
          let decimals = 18;
          try {
            decimals = await erc20Contract.decimals();
          } catch (e) {}

          const balance = await erc20Contract.balanceOf(tbaAddress);
          setTokenBalance(ethers.formatUnits(balance, decimals));
        } catch (error) {
          console.error("Erro ao buscar saldo do token ERC20:", error);
          setTokenBalance(null);
        }
      } else {
        setTokenBalance(null);
      }
    };
    
    // Pequeno debounce artificial para não spammar requests enquanto digita
    const timeoutId = setTimeout(() => {
      fetchTokenBalance();
    }, 500);

    return () => clearTimeout(timeoutId);
  }, [tokenAddress, activeTab, tbaAddress, provider]);

  const handleTransferNFT = async () => {
    if (!ethers.isAddress(targetAddress)) return alert("Endereço inválido!");
    try {
      setLoading(true);
      const tx = await contract.transferFrom(account, targetAddress, id);
      await tx.wait();
      alert(`Cartão #${id} transferido com sucesso!`);
      setTargetAddress("");
      onActionComplete();
    } catch (error: any) {
      alert("Falha ao transferir: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleDepositEth = async () => {
    if (!amount || isNaN(Number(amount))) return alert("Valor inválido!");
    try {
      setLoading(true);
      const value = ethers.parseEther(amount);
      const tx = await contract.depositEth(id, { value });
      await tx.wait();
      alert(`Depositado ${amount} ETH na TBA com sucesso!`);
      setAmount("");
    } catch (error: any) {
      alert("Falha no depósito: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleWithdrawEth = async () => {
    if (!ethers.isAddress(targetAddress)) return alert("Endereço de destino inválido!");
    if (!amount || isNaN(Number(amount))) return alert("Valor inválido!");
    try {
      setLoading(true);
      const value = ethers.parseEther(amount);
      const tx = await contract.withdrawEth(id, targetAddress, value);
      await tx.wait();
      alert(`Saque de ${amount} ETH realizado com sucesso!`);
      setTargetAddress("");
      setAmount("");
    } catch (error: any) {
      alert("Falha no saque: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  const handleWithdrawErc20 = async () => {
    if (!ethers.isAddress(targetAddress)) return alert("Endereço de destino inválido!");
    if (!ethers.isAddress(tokenAddress)) return alert("Contrato do token inválido!");
    if (!amount || isNaN(Number(amount))) return alert("Valor inválido!");
    try {
      setLoading(true);
      // Assumindo 18 decimais para simplificar
      const value = ethers.parseUnits(amount, 18);
      const tx = await contract.withdrawERC20(id, targetAddress, tokenAddress, value);
      await tx.wait();
      alert(`Saque de ERC-20 realizado com sucesso!`);
      setTargetAddress("");
      setAmount("");
      setTokenAddress("");
    } catch (error: any) {
      alert("Falha no saque de ERC20: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <motion.div 
      initial={{ opacity: 0, scale: 0.9 }}
      animate={{ opacity: 1, scale: 1 }}
      className="glass-card p-6 flex flex-col justify-between group hover:border-white/20 transition-all duration-300 relative overflow-hidden"
    >
      <div className="absolute top-0 right-0 w-32 h-32 bg-blue-500/10 rounded-full blur-3xl -mr-10 -mt-10 pointer-events-none"></div>
      
      <div className="mb-6">
        <div className="flex justify-between items-start mb-2">
          <span className="text-xs font-bold uppercase tracking-widest text-blue-400">HeroCard</span>
          <span className="bg-white/10 px-3 py-1 rounded-full text-xs font-mono">#{id}</span>
        </div>
        <h4 className="text-3xl font-bold text-white group-hover:bg-clip-text group-hover:text-transparent group-hover:bg-gradient-to-r group-hover:from-white group-hover:to-white/50 transition-all">
          Card {id}
        </h4>
        {tbaAddress && (
          <div className="mt-3 text-xs text-white/50 font-mono flex flex-col gap-1">
            <div 
              className="flex justify-between items-center bg-black/30 px-2 py-1.5 rounded border border-white/5 cursor-pointer hover:bg-black/50 transition-colors group/copy"
              onClick={() => copyToClipboard(tbaAddress)}
              title="Copiar endereço"
            >
              <span>TBA:</span>
              <div className="flex items-center gap-2">
                <span className="text-white/80">{tbaAddress.substring(0,8)}...{tbaAddress.substring(34)}</span>
                {copied ? <Check size={12} className="text-green-400" /> : <Copy size={12} className="text-white/40 group-hover/copy:text-white transition-colors" />}
              </div>
            </div>
            <div className="flex justify-between items-center bg-black/30 px-2 py-1.5 rounded border border-white/5">
              <span className="flex items-center gap-1"><Coins size={12} /> ETH:</span>
              <span className="text-white font-bold">{Number(ethBalance).toFixed(4)}</span>
            </div>
          </div>
        )}
      </div>

      <div className="flex gap-2 mb-4 bg-black/40 p-1 rounded-lg">
        <button 
          onClick={() => setActiveTab("nft")} 
          className={`flex-1 text-xs py-2 rounded-md transition-colors ${activeTab === "nft" ? "bg-white/10 text-white" : "text-white/50 hover:text-white"}`}
        >
          NFT
        </button>
        <button 
          onClick={() => setActiveTab("eth")} 
          className={`flex-1 text-xs py-2 rounded-md transition-colors ${activeTab === "eth" ? "bg-white/10 text-white" : "text-white/50 hover:text-white"}`}
        >
          ETH
        </button>
        <button 
          onClick={() => setActiveTab("erc20")} 
          className={`flex-1 text-xs py-2 rounded-md transition-colors ${activeTab === "erc20" ? "bg-white/10 text-white" : "text-white/50 hover:text-white"}`}
        >
          ERC20
        </button>
      </div>

      <div className="flex flex-col gap-3 min-h-[140px] justify-end">
        {activeTab === "nft" && (
          <>
            <input
              type="text"
              placeholder="0x... Recipient Address"
              className="bg-black/50 border border-white/10 rounded-lg px-4 py-3 text-sm focus:outline-none focus:border-blue-500/50 transition-colors w-full font-mono"
              value={targetAddress}
              onChange={(e) => setTargetAddress(e.target.value)}
            />
            <button
              onClick={handleTransferNFT}
              disabled={loading || !targetAddress}
              className="bg-blue-600 hover:bg-blue-500 disabled:opacity-50 disabled:bg-white/10 text-white rounded-lg px-4 py-3 flex items-center justify-center gap-2 text-sm font-semibold transition-all"
            >
              {loading ? <RefreshCw size={16} className="animate-spin" /> : <Send size={16} />}
              Transfer NFT
            </button>
          </>
        )}

        {activeTab === "eth" && (
          <>
            <input
              type="text"
              placeholder="Amount (ETH)"
              className="bg-black/50 border border-white/10 rounded-lg px-4 py-3 text-sm focus:outline-none focus:border-blue-500/50 transition-colors w-full font-mono"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
            <input
              type="text"
              placeholder="Withdraw to Address (0x...)"
              className="bg-black/50 border border-white/10 rounded-lg px-4 py-3 text-sm focus:outline-none focus:border-blue-500/50 transition-colors w-full font-mono"
              value={targetAddress}
              onChange={(e) => setTargetAddress(e.target.value)}
            />
            <div className="flex gap-2">
              <button
                onClick={handleDepositEth}
                disabled={loading || !amount}
                className="flex-1 bg-green-600 hover:bg-green-500 disabled:opacity-50 text-white rounded-lg py-3 flex items-center justify-center gap-2 text-sm font-semibold transition-all"
              >
                {loading ? <RefreshCw size={16} className="animate-spin" /> : <ArrowDownToLine size={16} />}
                Deposit
              </button>
              <button
                onClick={handleWithdrawEth}
                disabled={loading || !amount || !targetAddress}
                className="flex-1 bg-purple-600 hover:bg-purple-500 disabled:opacity-50 text-white rounded-lg py-3 flex items-center justify-center gap-2 text-sm font-semibold transition-all"
              >
                {loading ? <RefreshCw size={16} className="animate-spin" /> : <ArrowUpFromLine size={16} />}
                Withdraw
              </button>
            </div>
          </>
        )}

        {activeTab === "erc20" && (
          <>
            <input
              type="text"
              placeholder="Token Address (0x...)"
              className="bg-black/50 border border-white/10 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-blue-500/50 transition-colors w-full font-mono"
              value={tokenAddress}
              onChange={(e) => setTokenAddress(e.target.value)}
            />
            {tokenBalance !== null && (
              <div className="text-xs text-green-400 bg-green-400/10 px-3 py-2 rounded-lg border border-green-400/20 text-center font-mono">
                Saldo na TBA: {tokenBalance}
              </div>
            )}
            <input
              type="text"
              placeholder="Amount"
              className="bg-black/50 border border-white/10 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-blue-500/50 transition-colors w-full font-mono"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
            />
            <input
              type="text"
              placeholder="Withdraw to (0x...)"
              className="bg-black/50 border border-white/10 rounded-lg px-4 py-2 text-sm focus:outline-none focus:border-blue-500/50 transition-colors w-full font-mono"
              value={targetAddress}
              onChange={(e) => setTargetAddress(e.target.value)}
            />
            <button
              onClick={handleWithdrawErc20}
              disabled={loading || !amount || !targetAddress || !tokenAddress}
              className="w-full bg-purple-600 hover:bg-purple-500 disabled:opacity-50 text-white rounded-lg py-3 flex items-center justify-center gap-2 text-sm font-semibold transition-all"
            >
              {loading ? <RefreshCw size={16} className="animate-spin" /> : <Coins size={16} />}
              Withdraw ERC20
            </button>
            <span className="text-[10px] text-white/40 text-center mt-1">
              To deposit ERC20, send tokens directly to the TBA Wallet.
            </span>
          </>
        )}
      </div>
    </motion.div>
  );
}

export default function Home() {
  const [account, setAccount] = useState<string | null>(null);
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null);
  const [signer, setSigner] = useState<ethers.JsonRpcSigner | null>(null);
  const [contract, setContract] = useState<ethers.Contract | null>(null);
  
  const [myCards, setMyCards] = useState<string[]>([]);
  const [loading, setLoading] = useState<boolean>(false);

  useEffect(() => {
    if ((window as any).ethereum) {
      const _provider = new ethers.BrowserProvider((window as any).ethereum);
      setProvider(_provider);
      
      (window as any).ethereum.on('accountsChanged', (accounts: string[]) => {
        if (accounts.length > 0) {
          connectWallet();
        } else {
          setAccount(null);
        }
      });
    }
  }, []);

  const connectWallet = async () => {
    if (!provider) return;
    try {
      const accounts = await provider.send("eth_requestAccounts", []);
      const _signer = await provider.getSigner();
      const _contract = new ethers.Contract(CONTRACT_ADDRESS, HeroCardABI, _signer);
      
      setAccount(accounts[0]);
      setSigner(_signer);
      setContract(_contract);
      fetchMyCards(_contract, accounts[0]);
    } catch (error: any) {
      if (error.code === -32002 || error?.info?.error?.code === -32002 || error.message?.includes('-32002')) {
        alert("Já existe uma requisição de conexão pendente. Por favor, abra a extensão do MetaMask e confirme a conexão.");
      } else {
        console.error("Erro ao conectar carteira:", error);
      }
    }
  };

  const fetchMyCards = async (contractInstance: ethers.Contract, userAddress: string) => {
    try {
      setLoading(true);
      const totalSupply = await contractInstance.totalSupply();
      const owned = [];
      for (let i = 0; i < Number(totalSupply); i++) {
        try {
          const owner = await contractInstance.ownerOf(i);
          if (owner.toLowerCase() === userAddress.toLowerCase()) {
            owned.push(i.toString());
          }
        } catch (e) {
          // Token pode ter sido queimado
        }
      }
      setMyCards(owned);
    } catch (error) {
      console.error("Erro ao buscar cartões:", error);
    } finally {
      setLoading(false);
    }
  };

  const mintCard = async () => {
    if (!contract || !account) return;
    try {
      setLoading(true);
      const tx = await contract.mint(account, "ipfs://QmDummyTokenURI");
      await tx.wait();
      alert("HeroCard mintado com sucesso!");
      fetchMyCards(contract, account);
    } catch (error: any) {
      console.error("Erro ao mintar:", error);
      alert("Falha no mint: " + error.message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-[#0a0a0a] text-[#ededed] font-sans selection:bg-[#0070f3] selection:text-white">
      {/* Header Premium */}
      <header className="border-b border-white/5 bg-black/50 backdrop-blur-md sticky top-0 z-50">
        <div className="max-w-6xl mx-auto px-6 h-20 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-gradient-to-tr from-blue-600 to-purple-600 rounded-xl flex items-center justify-center glow-effect">
              <Layers size={20} className="text-white" />
            </div>
            <h1 className="text-xl font-bold tracking-tight bg-clip-text text-transparent bg-gradient-to-r from-white to-white/60">
              HeroCard App
            </h1>
          </div>

          <button
            onClick={connectWallet}
            className="flex items-center gap-2 bg-white/10 hover:bg-white/20 transition-all px-5 py-2.5 rounded-full text-sm font-medium border border-white/5 shadow-lg"
          >
            <Wallet size={16} />
            {account ? `${account.substring(0, 6)}...${account.substring(38)}` : "Connect Wallet"}
          </button>
        </div>
      </header>

      <main className="max-w-6xl mx-auto px-6 py-12">
        {/* Welcome Section */}
        <section className="mb-16 text-center max-w-2xl mx-auto pt-10">
          <motion.h2 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            className="text-5xl font-bold tracking-tighter mb-6"
          >
            The Ultimate <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-500 to-purple-500">Token Bound Account</span>
          </motion.h2>
          <motion.p 
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1 }}
            className="text-lg text-white/50 mb-10"
          >
            Mint your unique HeroCard NFT, which comes with its own built-in smart wallet (ERC-6551). Send and receive assets directly to your NFT.
          </motion.p>
          
          <motion.div 
            initial={{ opacity: 0, scale: 0.9 }}
            animate={{ opacity: 1, scale: 1 }}
            transition={{ delay: 0.2 }}
          >
            <button
              onClick={mintCard}
              disabled={!account || loading}
              className="bg-white text-black hover:bg-gray-200 disabled:opacity-50 disabled:cursor-not-allowed px-8 py-4 rounded-full font-bold text-lg transition-all shadow-[0_0_40px_rgba(255,255,255,0.2)] flex items-center justify-center gap-2 mx-auto"
            >
              {loading ? <RefreshCw className="animate-spin" /> : <Plus />}
              Mint HeroCard
            </button>
          </motion.div>
        </section>

        {/* User Cards Inventory */}
        {account && (
          <section className="pt-10 border-t border-white/5">
            <div className="flex items-center justify-between mb-8">
              <h3 className="text-2xl font-bold">My Vault</h3>
              <button onClick={() => fetchMyCards(contract!, account)} className="text-white/50 hover:text-white transition-colors">
                <RefreshCw size={20} className={loading ? "animate-spin" : ""} />
              </button>
            </div>

            {myCards.length === 0 && !loading ? (
              <div className="glass-card p-12 text-center text-white/40 border-dashed border-white/10">
                You don't own any HeroCards yet.
              </div>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
                <AnimatePresence>
                  {myCards.map((id) => (
                    <CardItem 
                      key={id} 
                      id={id} 
                      contract={contract!} 
                      account={account} 
                      provider={provider!}
                      onActionComplete={() => fetchMyCards(contract!, account)} 
                    />
                  ))}
                </AnimatePresence>
              </div>
            )}
          </section>
        )}
      </main>
    </div>
  );
}
