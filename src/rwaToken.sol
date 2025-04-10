// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/interfaces/IBlockVirtualGovernance.sol";
import "src/library/Errors.sol";

contract RwaToken is Initializable, OwnableUpgradeable, ERC20Upgradeable, UUPSUpgradeable {
    
    address public blockVirtualGovernance;
    uint256 public supportedCountryCode;

    event ComplianceChecked(address from, address to, bool isCompliant);
    event BlacklistChecked(address user, bool isBlacklisted);

    modifier onlyGovernance() {
        if (msg.sender != blockVirtualGovernance) revert Errors.UnauthorizedRole(msg.sender);
        _;
    }
    
    modifier notBlacklisted(address user) {
        if (IBlockVirtualGovernance(blockVirtualGovernance).isBlacklisted(address(this), user)) {
            revert Errors.UserBlacklisted(user);
        }
        _;
    }
    
    constructor() {
        // Used to avoid leaving an implementation contract uninitialized
        _disableInitializers();
    }

    function initialize(
        string memory name, 
        string memory symbol, 
        address governance,
        uint256 countryCode
    ) initializer public {
        if (governance == address(0)) revert Errors.ZeroAddress();
        
        __ERC20_init(name, symbol);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        blockVirtualGovernance = governance;
        supportedCountryCode = countryCode;
    }

    /// @notice This function is a special internal function that's part of the UUPS upgradeable contract's lifecycle.
    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}


    function mintRwa(address to, uint256 amount) public onlyGovernance notBlacklisted(to) {
        _mint(to, amount);
    }

    function burnRwa(address from, uint256 amount) public onlyGovernance notBlacklisted(from) {
        _burn(from, amount);
    }

    /**
     * @dev Checks if the transfer between two addresses is compliant
     * @param from Source address
     * @param to Destination address
     * @return isCompliant Whether the transfer is compliant
     */
    function checkCompliance(address from, address to) public view returns (bool isCompliant) {
        IBlockVirtualGovernance governance = IBlockVirtualGovernance(blockVirtualGovernance);
        
        // Check KYC and country restrictions
        bool fromKycStatus = governance.getKycStatus(from);
        bool toKycStatus = governance.getKycStatus(to);
        bool fromSupportedCountry = governance.isFromSupportedCountry(from);
        bool toSupportedCountry = governance.isFromSupportedCountry(to);
        
        // Check blacklist status
        bool fromBlacklisted = governance.isBlacklisted(address(this), from);
        bool toBlacklisted = governance.isBlacklisted(address(this), to);

        return fromKycStatus && toKycStatus && 
               fromSupportedCountry && toSupportedCountry && 
               !fromBlacklisted && !toBlacklisted;
    }

    /**
     * @dev Validate compliance for a transfer
     * @param from Source address
     * @param to Destination address
     */
    function _validateCompliance(address from, address to) internal view {
        bool isCompliant = checkCompliance(from, to);
        
        if (!isCompliant) {
            // Check specific reasons to provide better error messages
            IBlockVirtualGovernance governance = IBlockVirtualGovernance(blockVirtualGovernance);
            
            if (governance.isBlacklisted(address(this), from)) {
                revert Errors.UserBlacklisted(from);
            }
            
            if (governance.isBlacklisted(address(this), to)) {
                revert Errors.UserBlacklisted(to);
            }
            
            if (!governance.getKycStatus(from) || !governance.getKycStatus(to)) {
                revert Errors.UnauthorizedKycStatus();
            }
            
            if (!governance.isFromSupportedCountry(from) || !governance.isFromSupportedCountry(to)) {
                revert Errors.UnauthorizedCountryUser();
            }
        }
    }

    /**
     * @dev Check if a user is blacklisted for this token
     * @param user Address to check
     * @return True if the user is blacklisted
     */
    function isBlacklisted(address user) public view returns (bool) {
        return IBlockVirtualGovernance(blockVirtualGovernance).isBlacklisted(address(this), user);
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        _validateCompliance(msg.sender, to);
        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        _validateCompliance(from, to);
        return super.transferFrom(from, to, value);
    }
}