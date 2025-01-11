const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Flash Loan", function () {
    let FlashLoan, flashLoan, TestToken, token;
    let owner, user, liquidityProvider;
    
    const INITIAL_LIQUIDITY = ethers.utils.parseEther("1000000");
    const FLASH_LOAN_AMOUNT = ethers.utils.parseEther("1000");
    
    beforeEach(async function () {
        [owner, user, liquidityProvider] = await ethers.getSigners();
        
        // Deploy test token
        TestToken = await ethers.getContractFactory("TestToken");
        token = await TestToken.deploy();
        await token.deployed();
        
        // Deploy flash loan contract
        FlashLoan = await ethers.getContractFactory("FlashLoan");
        flashLoan = await FlashLoan.deploy();
        await flashLoan.deployed();
        
        // Fund pool with initial liquidity
        await token.mint(liquidityProvider.address, INITIAL_LIQUIDITY);
        await token.connect(liquidityProvider).approve(flashLoan.address, INITIAL_LIQUIDITY);
        await flashLoan.connect(liquidityProvider).fundPool(token.address, INITIAL_LIQUIDITY);
    });
    
    describe("Pool Funding", function () {
        it("Should fund pool correctly", async function () {
            const balance = await flashLoan.getPoolBalance(token.address);
            expect(balance).to.equal(INITIAL_LIQUIDITY);
        });
    });
    
    describe("Flash Loan Execution", function () {
        it("Should execute flash loan", async function () {
            // Deploy mock receiver
            const MockReceiver = await ethers.getContractFactory("MockFlashLoanReceiver");
            const receiver = await MockReceiver.deploy(flashLoan.address, token.address);
            await receiver.deployed();
            
            await expect(
                receiver.connect(user).executeFlashLoan(FLASH_LOAN_AMOUNT)
            ).to.emit(flashLoan, "FlashLoan")
             .withArgs(
                 token.address,
                 receiver.address,
                 FLASH_LOAN_AMOUNT,
                 FLASH_LOAN_AMOUNT.mul(9).div(10000)
             );
        });
        
        it("Should fail if loan not repaid", async function () {
            const BadReceiver = await ethers.getContractFactory("BadFlashLoanReceiver");
            const receiver = await BadReceiver.deploy(flashLoan.address);
            await receiver.deployed();
            
            await expect(
                receiver.connect(user).executeFlashLoan(FLASH_LOAN_AMOUNT)
            ).to.be.revertedWith("Flash loan not repaid");
        });
    });
}); 