// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRwaPriceFeed
 * @dev Interface for RWA token price feed
 */
interface IRwaPriceFeed {
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
    ) external view returns (uint256);
} 