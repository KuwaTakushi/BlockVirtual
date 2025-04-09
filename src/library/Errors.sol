// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library Errors {

    error ZeroAddress();
    error InvalidAmount();
    error UnauthorizedKycStatus();
    error UnauthorizedRole(address account);
    error UnauthorizeCountryRole(address account, uint256 countryCode);
    error UnauthorizedCountryUser();

    error InsufficientBalance();
    error UserBlacklisted(address account);
    error ContractPaused();
    error ExceedsLimit(uint256 amount, uint256 limit);
    error VaultPaused();
    
    error InvalidAddress();
    error InvalidVault();
    error InvalidTokenPair();
    error InvalidPrice();

    error TransferFailed();
    error SwapFailed();
    error SlippageTooHigh();
    error InsufficientAmount();
    error VaultNotFound();
    
    error PriceNotAvailable();
    error TokenAlreadyRegistered();
}