// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRwaPriceFeed {

    function calculateConversion(
        address fromToken,
        address toToken,
        uint256 amountIn
    ) external view returns (uint256);
} 