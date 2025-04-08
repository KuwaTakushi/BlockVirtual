// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "src/library/Errors.sol";

type VaultStatus is bool;

library VaultManager {
    struct VaultRegistry {
        VaultStatus status;
        address pauser;
    }

    function pauseVault(
        mapping(address => VaultRegistry) storage registry,
        address vault
    ) internal {
        if (vault == address(0)) revert Errors.ZeroAddress();
        registry[vault] = VaultRegistry({
            status: VaultStatus.wrap(false),
            pauser: msg.sender
        });
    }
    
    function unpauseVault(
        mapping(address => VaultRegistry) storage registry,
        address vault
    ) internal {
        if (vault == address(0)) revert Errors.ZeroAddress();
        registry[vault].status = VaultStatus.wrap(true);
    }

    function isVaultPaused(
        mapping(address => VaultRegistry) storage registry,
        address vault
    ) internal view returns (bool) {
        return !VaultStatus.unwrap(registry[vault].status);
    }
} 