// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBlockVirtualGovernance {

    function getKycStatus(address user) external view returns (bool);
    function blacklisted(address user) external view returns (bool);
    function isFromSupportedCountry(address user) external view returns (bool);
    function isVaultPaused(address vault) external view returns (bool);
}