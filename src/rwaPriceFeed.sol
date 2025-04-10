// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "src/library/Errors.sol";

/**
 * @title BlockVirtualPriceFeed
 * @dev Simplified price feed for BlockVirtual's Central Asia expansion
 */
contract BlockVirtualPriceFeed is AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    
    struct PriceInfo {
        uint256 price;
        uint256 timestamp;
    }
    
    mapping(address => PriceInfo) public tokenPrices;
    
    address[] public registeredTokens;
    
    mapping(address => bool) private _isTokenRegistered;
    
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
        if (token == address(0)) revert Errors.ZeroAddress();
        if (_isTokenRegistered[token]) revert Errors.TokenAlreadyRegistered();
        
        registeredTokens.push(token);
        _isTokenRegistered[token] = true;
        
        emit TokenRegistered(token);
    }
    
    /**
     * @dev Update price for a token
     * @param token Token contract address
     * @param price New price
     */
    function updatePrice(address token, uint256 price) external onlyRole(PRICE_UPDATER_ROLE) {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (price == 0) revert Errors.InvalidAmount();
        if (!_isTokenRegistered[token]) revert Errors.InvalidAddress();
        
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
        if (token == address(0)) revert Errors.ZeroAddress();
        if (tokenPrices[token].price == 0) revert Errors.PriceNotAvailable();
        
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
        
        if (fromPrice == 0 || toPrice == 0) revert Errors.PriceNotAvailable();
        
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
        return _isTokenRegistered[token];
    }
}