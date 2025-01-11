// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./interfaces/IFlashLoanReceiver.sol";
import "./interfaces/IPriceOracle.sol";

contract FlashLoanV2 is ReentrancyGuard, Ownable, Pausable {
    struct TokenConfig {
        bool supported;
        uint256 baseFee;
        uint256 utilizationFee;
        uint256 totalLiquidity;
        uint256 totalBorrowed;
        uint256 rewardRate;
    }
    
    struct LiquidityProvider {
        uint256 liquidity;
        uint256 lastUpdateTime;
        uint256 rewardDebt;
    }
    
    mapping(address => TokenConfig) public tokenConfigs;
    mapping(address => mapping(address => LiquidityProvider)) public liquidityProviders;
    mapping(address => uint256) public totalRewards;
    
    IPriceOracle public priceOracle;
    uint256 public constant MAX_UTILIZATION = 80; // 80%
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public minLoanDuration;
    uint256 public maxLoanDuration;
    
    event FlashLoan(
        address indexed token,
        address indexed borrower,
        uint256 amount,
        uint256 fee,
        uint256 duration
    );
    
    event LiquidityAdded(
        address indexed token,
        address indexed provider,
        uint256 amount,
        uint256 reward
    );
    
    event RewardClaimed(
        address indexed provider,
        address indexed token,
        uint256 amount
    );
    
    constructor(address _priceOracle) {
        priceOracle = IPriceOracle(_priceOracle);
        minLoanDuration = 1 block;
        maxLoanDuration = 100 blocks;
    }
    
    function executeFlashLoan(
        address[] calldata tokens,
        uint256[] calldata amounts,
        uint256 duration,
        bytes calldata params
    ) external nonReentrant whenNotPaused {
        require(tokens.length == amounts.length, "Array length mismatch");
        require(duration >= minLoanDuration && duration <= maxLoanDuration, "Invalid duration");
        
        uint256 totalValueLocked = 0;
        uint256[] memory fees = new uint256[](tokens.length);
        
        // Calculate fees and check liquidity
        for (uint256 i = 0; i < tokens.length; i++) {
            require(tokenConfigs[tokens[i]].supported, "Token not supported");
            
            TokenConfig storage config = tokenConfigs[tokens[i]];
            uint256 utilization = (config.totalBorrowed * 10000) / config.totalLiquidity;
            require(utilization <= MAX_UTILIZATION, "Utilization too high");
            
            fees[i] = calculateFee(tokens[i], amounts[i], utilization);
            totalValueLocked += (amounts[i] + fees[i]) * priceOracle.getPrice(tokens[i]);
        }
        
        // Transfer tokens and execute operation
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i]).transfer(msg.sender, amounts[i]);
            tokenConfigs[tokens[i]].totalBorrowed += amounts[i];
        }
        
        // Execute borrower's logic
        IFlashLoanReceiver(msg.sender).executeOperation(
            tokens,
            amounts,
            fees,
            params
        );
        
        // Verify repayment and update state
        for (uint256 i = 0; i < tokens.length; i++) {
            TokenConfig storage config = tokenConfigs[tokens[i]];
            require(
                IERC20(tokens[i]).balanceOf(address(this)) >= 
                config.totalLiquidity + fees[i],
                "Insufficient repayment"
            );
            
            config.totalBorrowed -= amounts[i];
            config.totalLiquidity += fees[i];
            
            emit FlashLoan(
                tokens[i],
                msg.sender,
                amounts[i],
                fees[i],
                duration
            );
        }
    }
    
    function addLiquidity(address token, uint256 amount) external nonReentrant {
        require(tokenConfigs[token].supported, "Token not supported");
        require(amount > 0, "Amount must be greater than 0");
        
        TokenConfig storage config = tokenConfigs[token];
        LiquidityProvider storage provider = liquidityProviders[token][msg.sender];
        
        // Calculate and distribute rewards
        uint256 reward = calculateReward(token, msg.sender);
        if (reward > 0) {
            totalRewards[token] += reward;
            provider.rewardDebt += reward;
        }
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        provider.liquidity += amount;
        provider.lastUpdateTime = block.timestamp;
        config.totalLiquidity += amount;
        
        emit LiquidityAdded(token, msg.sender, amount, reward);
    }
    
    function claimRewards(address token) external nonReentrant {
        LiquidityProvider storage provider = liquidityProviders[token][msg.sender];
        uint256 reward = calculateReward(token, msg.sender);
        require(reward > 0, "No rewards to claim");
        
        provider.rewardDebt = 0;
        provider.lastUpdateTime = block.timestamp;
        totalRewards[token] -= reward;
        
        IERC20(token).transfer(msg.sender, reward);
        
        emit RewardClaimed(msg.sender, token, reward);
    }
    
    // Internal functions
    function calculateFee(
        address token,
        uint256 amount,
        uint256 utilization
    ) internal view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        uint256 baseFee = (amount * config.baseFee) / FEE_DENOMINATOR;
        uint256 utilizationFee = (amount * config.utilizationFee * utilization) / (FEE_DENOMINATOR * 100);
        return baseFee + utilizationFee;
    }
    
    function calculateReward(
        address token,
        address provider
    ) internal view returns (uint256) {
        LiquidityProvider storage lp = liquidityProviders[token][provider];
        TokenConfig storage config = tokenConfigs[token];
        
        uint256 timeElapsed = block.timestamp - lp.lastUpdateTime;
        return (lp.liquidity * config.rewardRate * timeElapsed) / (24 hours * FEE_DENOMINATOR);
    }
    
    // Admin functions
    function addSupportedToken(
        address token,
        uint256 baseFee,
        uint256 utilizationFee,
        uint256 rewardRate
    ) external onlyOwner {
        require(!tokenConfigs[token].supported, "Token already supported");
        
        tokenConfigs[token] = TokenConfig({
            supported: true,
            baseFee: baseFee,
            utilizationFee: utilizationFee,
            totalLiquidity: 0,
            totalBorrowed: 0,
            rewardRate: rewardRate
        });
    }
    
    function updateTokenConfig(
        address token,
        uint256 baseFee,
        uint256 utilizationFee,
        uint256 rewardRate
    ) external onlyOwner {
        require(tokenConfigs[token].supported, "Token not supported");
        
        TokenConfig storage config = tokenConfigs[token];
        config.baseFee = baseFee;
        config.utilizationFee = utilizationFee;
        config.rewardRate = rewardRate;
    }
    
    function setLoanDurationLimits(
        uint256 _minDuration,
        uint256 _maxDuration
    ) external onlyOwner {
        require(_minDuration < _maxDuration, "Invalid duration limits");
        minLoanDuration = _minDuration;
        maxLoanDuration = _maxDuration;
    }
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    // View functions
    function getUtilizationRate(address token) external view returns (uint256) {
        TokenConfig storage config = tokenConfigs[token];
        return (config.totalBorrowed * 10000) / config.totalLiquidity;
    }
    
    function getPendingRewards(address token, address provider) external view returns (uint256) {
        return calculateReward(token, provider);
    }
} 