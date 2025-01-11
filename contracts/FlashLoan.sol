// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IFlashLoanReceiver.sol";

contract FlashLoan is ReentrancyGuard, Ownable {
    mapping(address => uint256) public poolBalance;
    mapping(address => bool) public supportedTokens;
    
    uint256 public constant FLASH_LOAN_FEE = 9; // 0.09%
    uint256 public constant FEE_DENOMINATOR = 10000;
    
    event FlashLoan(
        address indexed token,
        address indexed borrower,
        uint256 amount,
        uint256 fee
    );
    
    event PoolFunded(
        address indexed token,
        address indexed funder,
        uint256 amount
    );
    
    constructor() {}
    
    function executeFlashLoan(
        address token,
        uint256 amount,
        bytes calldata params
    ) external nonReentrant {
        require(supportedTokens[token], "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "Insufficient liquidity"
        );
        
        uint256 fee = (amount * FLASH_LOAN_FEE) / FEE_DENOMINATOR;
        uint256 amountToRepay = amount + fee;
        
        // Transfer tokens to borrower
        IERC20(token).transfer(msg.sender, amount);
        
        // Execute borrower's logic
        IFlashLoanReceiver(msg.sender).executeOperation(
            token,
            amount,
            fee,
            params
        );
        
        // Verify repayment
        require(
            IERC20(token).balanceOf(address(this)) >= poolBalance[token] + fee,
            "Flash loan not repaid"
        );
        
        // Update pool balance
        poolBalance[token] += fee;
        
        emit FlashLoan(token, msg.sender, amount, fee);
    }
    
    function fundPool(address token, uint256 amount) external {
        require(amount > 0, "Amount must be greater than 0");
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        poolBalance[token] += amount;
        supportedTokens[token] = true;
        
        emit PoolFunded(token, msg.sender, amount);
    }
    
    function withdrawFees(address token, uint256 amount) external onlyOwner {
        require(amount <= poolBalance[token], "Insufficient fees");
        
        poolBalance[token] -= amount;
        IERC20(token).transfer(msg.sender, amount);
    }
    
    function getPoolBalance(address token) external view returns (uint256) {
        return poolBalance[token];
    }
} 