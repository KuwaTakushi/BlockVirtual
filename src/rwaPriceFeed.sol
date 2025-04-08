// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BlockVirtualPriceFeed
 * @dev Simplified price feed for BlockVirtual's Central Asia expansion
 */
contract BlockVirtualPriceFeed is AccessControl {
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    
    // Price structure
    struct PriceInfo {
        uint256 price;
        uint256 timestamp;
    }
    
    // Asset prices (tokenAddress => price info)
    mapping(address => PriceInfo) public tokenPrices;
    
    // List of registered tokens
    address[] public registeredTokens;
    
    // Events
    event PriceUpdated(address indexed token, uint256 price, uint256 timestamp);
    event TokenRegistered(address indexed token);
    
    /**
     * @dev Constructor
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(PRICE_UPDATER_ROLE, msg.sender);
    }
    
    /**
     * @dev Register new token
     * @param token Token contract address
     */
    function registerToken(address token) external onlyRole(ADMIN_ROLE) {
        require(token != address(0), "Invalid token address");
        require(tokenPrices[token].timestamp == 0, "Token already registered");
        
        registeredTokens.push(token);
        
        emit TokenRegistered(token);
    }
    
    /**
     * @dev Update price for a token
     * @param token Token contract address
     * @param price New price
     */
    function updatePrice(address token, uint256 price) external onlyRole(PRICE_UPDATER_ROLE) {
        require(token != address(0), "Invalid token address");
        require(price > 0, "Price must be positive");
        
        tokenPrices[token] = PriceInfo({
            price: price,
            timestamp: block.timestamp
        });
        
        emit PriceUpdated(token, price, block.timestamp);
    }
    
    /**
     * @dev Get latest price for a token
     * @param token Token contract address
     * @return Latest price
     */
    function getLatestPrice(address token) external view returns (uint256) {
        require(token != address(0), "Invalid token address");
        require(tokenPrices[token].price > 0, "No price available");
        
        return tokenPrices[token].price;
    }
    
    /**
     * @dev Calculate conversion between tokens
     * @param fromToken Source token address
     * @param toToken Destination token address
     * @param amountIn Amount of source token
     * @return amountOut Equivalent amount in destination token
     */
    function calculateConversion(
        address fromToken, 
        address toToken, 
        uint256 amountIn
    ) external view returns (uint256) {
        // If same token, return same amount
        if (fromToken == toToken) return amountIn;
        
        uint256 fromPrice = tokenPrices[fromToken].price;
        uint256 toPrice = tokenPrices[toToken].price;
        
        require(fromPrice > 0 && toPrice > 0, "Price not available");
        
        // Calculate conversion
        return (amountIn * fromPrice) / toPrice;
    }
    
    /**
     * @dev Get all registered tokens
     * @return Array of token addresses
     */
    function getAllTokens() external view returns (address[] memory) {
        return registeredTokens;
    }
    
    /**
     * @dev Get token price timestamp
     * @param token Token contract address
     * @return Price timestamp
     */
    function getPriceTimestamp(address token) external view returns (uint256) {
        return tokenPrices[token].timestamp;
    }
    
    /**
     * @dev Check if token is registered
     * @param token Token contract address
     * @return True if registered
     */
    function isTokenRegistered(address token) external view returns (bool) {
        return tokenPrices[token].timestamp > 0;
    }
}