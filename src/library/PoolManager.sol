// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "src/library/Errors.sol";

type PoolStatus is bool;

library PoolManager {
    struct PoolRegistry {
        PoolStatus status; 
        address poolAddress;
        address operator;
        uint256 registrationTime;
    }

    function registerPool(
        mapping(address => PoolRegistry) storage registry,
        address pool
    ) internal {
        if (pool == address(0)) revert Errors.ZeroAddress();
        
        registry[pool] = PoolRegistry({
            status: PoolStatus.wrap(true),
            poolAddress: pool,
            operator: msg.sender,
            registrationTime: block.timestamp
        });
    }
    
    function deactivatePool(
        mapping(address => PoolRegistry) storage registry,
        address pool
    ) internal {
        if (pool == address(0)) revert Errors.ZeroAddress();
        if (registry[pool].poolAddress == address(0)) revert Errors.InvalidPool();
        
        registry[pool].status = PoolStatus.wrap(false);
        registry[pool].operator = msg.sender;
    }
    
    function activatePool(
        mapping(address => PoolRegistry) storage registry,
        address pool
    ) internal {
        if (pool == address(0)) revert Errors.ZeroAddress();
        if (registry[pool].poolAddress == address(0)) revert Errors.InvalidPool();
        
        registry[pool].status = PoolStatus.wrap(true);
        registry[pool].operator = msg.sender;
    }
    
    function isPoolActive(
        mapping(address => PoolRegistry) storage registry,
        address pool
    ) internal view returns (bool) {
        return registry[pool].poolAddress != address(0) && 
               PoolStatus.unwrap(registry[pool].status);
    }

    function isPoolRegistered(
        mapping(address => PoolRegistry) storage registry,
        address pool
    ) internal view returns (bool) {
        return registry[pool].poolAddress != address(0);
    }
    

    function getPoolOperator(
        mapping(address => PoolRegistry) storage registry,
        address pool
    ) internal view returns (address) {
        return registry[pool].operator;
    }
    

    function getPoolRegistrationTime(
        mapping(address => PoolRegistry) storage registry,
        address pool
    ) internal view returns (uint256) {
        return registry[pool].registrationTime;
    }
} 