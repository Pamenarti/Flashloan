const ethers = require('ethers');
const Web3 = require('web3');
const dotenv = require('dotenv');
const flashLoanABI = require('./artifacts/contracts/FlashLoan.sol/FlashLoan.json').abi;

class FlashLoanService {
    constructor() {
        dotenv.config();
        this.provider = new ethers.providers.JsonRpcProvider(process.env.RPC_URL);
        this.wallet = new ethers.Wallet(process.env.PRIVATE_KEY, this.provider);
        this.contractAddress = process.env.FLASH_LOAN_ADDRESS;
    }
    
    async initializeContract() {
        this.contract = new ethers.Contract(
            this.contractAddress,
            flashLoanABI,
            this.provider
        );
        this.contractWithSigner = this.contract.connect(this.wallet);
    }
    
    async executeFlashLoan(token, amount, params) {
        const tx = await this.contractWithSigner.executeFlashLoan(
            token,
            amount,
            params
        );
        return await tx.wait();
    }
    
    async fundPool(token, amount) {
        const tokenContract = new ethers.Contract(
            token,
            ['function approve(address spender, uint256 amount) external returns (bool)'],
            this.wallet
        );
        
        await tokenContract.approve(this.contractAddress, amount);
        
        const tx = await this.contractWithSigner.fundPool(token, amount);
        return await tx.wait();
    }
    
    async getPoolBalance(token) {
        return await this.contract.getPoolBalance(token);
    }
    
    async listenToEvents() {
        this.contract.on("FlashLoan", (token, borrower, amount, fee, event) => {
            console.log(`
                Flash Loan Executed:
                Token: ${token}
                Borrower: ${borrower}
                Amount: ${ethers.utils.formatEther(amount)}
                Fee: ${ethers.utils.formatEther(fee)}
            `);
        });
        
        this.contract.on("PoolFunded", (token, funder, amount, event) => {
            console.log(`
                Pool Funded:
                Token: ${token}
                Funder: ${funder}
                Amount: ${ethers.utils.formatEther(amount)}
            `);
        });
    }
    
    // Helper functions for arbitrage calculations
    async calculateArbitrageProfitability(
        token,
        amount,
        sourceExchange,
        targetExchange
    ) {
        const sourcePrice = await this.getTokenPrice(token, sourceExchange);
        const targetPrice = await this.getTokenPrice(token, targetExchange);
        
        const profit = (targetPrice - sourcePrice) * amount;
        const fee = (amount * 9) / 10000; // 0.09% fee
        
        return {
            profit,
            fee,
            netProfit: profit - fee,
            profitable: profit > fee
        };
    }
    
    async getTokenPrice(token, exchange) {
        // Implement price fetching logic for different DEXes
        return 0;
    }
}

module.exports = FlashLoanService; 