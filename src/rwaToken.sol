// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "src/interfaces/IBlockVirtualGovernance.sol";
import "src/library/Errors.sol";

contract RwaToken is Initializable, OwnableUpgradeable, ERC20Upgradeable, UUPSUpgradeable   {
    
    address public blockVirtualGovernance;
    uint256 public supportedCountryCode;

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
        __ERC20_init(name, symbol);
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        blockVirtualGovernance = governance;
        supportedCountryCode = countryCode;
    }

    /// @notice This function is a special internal function that's part of the UUPS upgradeable contract's lifecycle.
    function _authorizeUpgrade(address newImplementation) internal onlyOwner virtual override {}

    function mintRwa(address to, uint256 amount) public {
        require(msg.sender == blockVirtualGovernance, Errors.UnauthorizedRole(msg.sender));
        _mint(to, amount);
    }

    function burnRwa(address to, uint256 amount) public {
        require(msg.sender == blockVirtualGovernance, Errors.UnauthorizedRole(msg.sender));
        _burn(to, amount);
    }

    function transfer(address to, uint256 value) public virtual override returns (bool) {
        bool fromKycStatus = IBlockVirtualGovernance(blockVirtualGovernance).getKycStatus(msg.sender);
        bool toKycStatus = IBlockVirtualGovernance(blockVirtualGovernance).getKycStatus(to);
        bool fromSupportedCountry = IBlockVirtualGovernance(blockVirtualGovernance).isFromSupportedCountry(msg.sender);
        bool toSupportedCountry = IBlockVirtualGovernance(blockVirtualGovernance).isFromSupportedCountry(to);

        require(fromKycStatus && toKycStatus, Errors.UnauthorizedKycStatus());
        require(fromSupportedCountry && toSupportedCountry, Errors.UnauthorizedCountryUser());

        return super.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public virtual override returns (bool) {
        bool fromKycStatus = IBlockVirtualGovernance(blockVirtualGovernance).getKycStatus(from);
        bool toKycStatus = IBlockVirtualGovernance(blockVirtualGovernance).getKycStatus(to);
        bool fromSupportedCountry = IBlockVirtualGovernance(blockVirtualGovernance).isFromSupportedCountry(from);
        bool toSupportedCountry = IBlockVirtualGovernance(blockVirtualGovernance).isFromSupportedCountry(to);

        require(fromKycStatus && toKycStatus, Errors.UnauthorizedKycStatus());
        require(fromSupportedCountry && toSupportedCountry, Errors.UnauthorizedCountryUser());
                
        return super.transferFrom(from, to, value);
    }
}