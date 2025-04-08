// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import  "src/library/Errors.sol";

type KYCStatus is bool;

library KYCManager {

    struct KYCRegistry {
        KYCStatus status;
        uint256 countryCode;
        uint256 verificationTime;
        uint256 expiryTime;
        address verifier;
    }

    function addKYC(
        mapping(address => KYCRegistry) storage registry,
        address user,
        uint256 expiryTime,
        uint256 countryCode,
        address verifier
    ) internal {
        registry[user] = KYCRegistry({
            status: KYCStatus.wrap(true),
            countryCode: countryCode,
            verificationTime: block.timestamp,
            expiryTime: expiryTime,
            verifier: verifier
        });
    }

    function updateKYC(
        mapping(address => KYCRegistry) storage registry,
        address user,
        bool status,
        uint256 expiryTime,
        uint256 countryCode,
        address verifier
    ) internal {
        require(user != address(0), Errors.ZeroAddress());

        registry[user].status = KYCStatus.wrap(status);
        registry[user].verificationTime = block.timestamp;
        registry[user].expiryTime = expiryTime;
        registry[user].verifier = verifier;
        registry[user].countryCode = countryCode;
    }

    function removeKYC(
        mapping(address => KYCRegistry) storage registry,
        address user
    ) internal {
        delete registry[user];
    }

    function isKYCVerified(
        mapping(address => KYCRegistry) storage registry,
        address user
    ) internal view returns (bool) {
        return KYCStatus.unwrap(registry[user].status) && 
               (registry[user].expiryTime == 0 || registry[user].expiryTime > block.timestamp);
    }

    function getCountryCode(
        mapping(address => KYCRegistry) storage registry,
        address user
    ) internal view returns (uint256) {
        return registry[user].countryCode;
    }
}