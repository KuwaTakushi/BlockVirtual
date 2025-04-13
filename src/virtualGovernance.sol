// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "src/library/KYCManager.sol";
import "src/library/PoolManager.sol";
import "src/library/Errors.sol";

contract BlockVirtualGovernance is Initializable, AccessControlUpgradeable {

    using KYCManager for mapping(address => KYCManager.KYCRegistry);
    using PoolManager for mapping(address => PoolManager.PoolRegistry);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REGULATOR_ROLE = keccak256("REGULATOR_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant BANK_PARTNER_ROLE = keccak256("BANK_PARTNER_ROLE");

    mapping (address => KYCManager.KYCRegistry) public registry;
    mapping (uint256 => bool) public supportedCountryCode;
    mapping (address => PoolManager.PoolRegistry) public poolRegistry;
    
    // Blacklist management - token address => user address => blacklist status
    mapping (address => mapping(address => bool)) public blacklisted;
    
    event PoolRegistered(address indexed pool, address indexed registrar);
    event PoolActivated(address indexed pool, address indexed activator);
    event PoolDeactivated(address indexed pool, address indexed deactivator);
    event UserBlacklisted(address indexed token, address indexed user, address indexed operator);
    event UserRemovedFromBlacklist(address indexed token, address indexed user, address indexed operator);

    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    
    modifier onlyBlackListedOperator() {
        if (!hasRole(ADMIN_ROLE, msg.sender) && !hasRole(REGULATOR_ROLE, msg.sender)
            ) revert Errors.UnauthorizedRole(msg.sender);
        _;
    }

    modifier onlyKycOperator() {
        if (!hasRole(ADMIN_ROLE, msg.sender) && !hasRole(REGULATOR_ROLE, msg.sender)
            ) revert Errors.UnauthorizedRole(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                            COUNTRY CONTROL
    //////////////////////////////////////////////////////////////*/
    function addSupportedCountryCode(uint256 countryCode) public onlyRole(ADMIN_ROLE) {
        supportedCountryCode[countryCode] = true;
    }

    function removeSupportedCountryCode(uint256 countryCode) public onlyRole(ADMIN_ROLE) {
        supportedCountryCode[countryCode] = false;
    }  

    /*//////////////////////////////////////////////////////////////
                            BLACKLISTED CONTROL
    //////////////////////////////////////////////////////////////*/    
    /**
     * @dev Add a user to the blacklist for a specific token
     * @param token The token address
     * @param account The user address to blacklist
     */
    function addBlacklisted(address token, address account) public onlyBlackListedOperator {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (account == address(0)) revert Errors.ZeroAddress();
        
        blacklisted[token][account] = true;
        emit UserBlacklisted(token, account, msg.sender);
    }

    /**
     * @dev Remove a user from the blacklist for a specific token
     * @param token The token address
     * @param account The user address to remove from blacklist
     */
    function removeBlacklisted(address token, address account) public onlyBlackListedOperator {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (account == address(0)) revert Errors.ZeroAddress();
        
        blacklisted[token][account] = false;
        emit UserRemovedFromBlacklist(token, account, msg.sender);
    }
    
    /**
     * @dev Check if a user is blacklisted for a specific token
     * @param token The token address
     * @param account The user address to check
     * @return True if the user is blacklisted for the token
     */
    function isBlacklisted(address token, address account) public view returns (bool) {
        return blacklisted[token][account];
    }

    /*//////////////////////////////////////////////////////////////
                            KYC CONTROL
    //////////////////////////////////////////////////////////////*/    
    function registerKYCUser(
        address user,
        uint256 expiryTime,
        uint256 countryCode
    ) public onlyKycOperator {
        registry.addKYC(user, expiryTime, countryCode, msg.sender);
    }

    function updateKYCUser(
        address user,
        bool status,
        uint256 expiryTime,
        uint256 countryCode
    ) public onlyKycOperator {
        registry.updateKYC(user, status, expiryTime, countryCode, msg.sender);
    }

    function removeKYCUser(address user) public onlyRole(ADMIN_ROLE) {
        registry.removeKYC(user);
    }

    function isFromSupportedCountry(address user) public view returns (bool) {
        return registry.getCountryCode(user) != 0 && supportedCountryCode[registry.getCountryCode(user)];
    }

    function getKycStatus(address user) public view returns (bool) {
        return registry.isKYCVerified(user);
    }

    /*//////////////////////////////////////////////////////////////
                            POOL CONTROL
    //////////////////////////////////////////////////////////////*/
    function registerPool(address pool) external onlyRole(ADMIN_ROLE) {
        poolRegistry.registerPool(pool);
        emit PoolRegistered(pool, msg.sender);
    }

    function activatePool(address pool) external onlyRole(ADMIN_ROLE) {
        poolRegistry.activatePool(pool);
        emit PoolActivated(pool, msg.sender);
    }

    function deactivatePool(address pool) external onlyRole(ADMIN_ROLE) {
        poolRegistry.deactivatePool(pool);
        emit PoolDeactivated(pool, msg.sender);
    }

    function isPoolActive(address pool) external view returns (bool) {
        return poolRegistry.isPoolActive(pool);
    }

    function isPoolRegistered(address pool) external view returns (bool) {
        return poolRegistry.isPoolRegistered(pool);
    }

    function getPoolOperator(address pool) external view returns (address) {
        return poolRegistry.getPoolOperator(pool);
    }

    function getPoolRegistrationTime(address pool) external view returns (uint256) {
        return poolRegistry.getPoolRegistrationTime(pool);
    }

    /*//////////////////////////////////////////////////////////////
                            ROLE CONTROL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Sets the admin role for a specified role
     * @param role The role for which to set the admin role
     * @param adminRole The role that will administer the specified role
     * Only DEFAULT_ADMIN_ROLE can call this function
     */
    function setRoleAdmin(bytes32 role, bytes32 adminRole) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setRoleAdmin(role, adminRole);
    }
    
    /**
     * @dev Sets up the administrative hierarchy for all roles
     * This should be called once after initialization to establish role relationships
     * Only DEFAULT_ADMIN_ROLE can call this function
     *
     * Role Administrative Hierarchy:
     * - DEFAULT_ADMIN_ROLE manages all roles by default
     * - ADMIN_ROLE manages operational roles
     * - REGULATOR_ROLE manages country-specific regulatory roles
     * - COMPLIANCE_ROLE manages KYC verification personnel
     */
    function setupRoleAdmins() external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Set admins for primary operational roles
        _setRoleAdmin(REGULATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(COMPLIANCE_ROLE, ADMIN_ROLE);
        
        // Country-specific regulatory roles are managed by the general regulatory role
        _setRoleAdmin(OPERATOR_ROLE, REGULATOR_ROLE);
    }
    
    /**
     * @dev Grants the REGULATOR_ROLE to an account
     * @param account Address to receive the role
     * Only ADMIN_ROLE can call this function
     */
    function grantRegulatorRole(address account) public onlyRole(ADMIN_ROLE) {
        grantRole(REGULATOR_ROLE, account);
    }
    
    /**
     * @dev Grants the OPERATOR_ROLE to an account
     * @param account Address to receive the role
     * Only REGULATOR_ROLE can call this function
     *
     * This role is responsible for implementing country-specific
     * regulations and working with local authorities
     */
    function grantOperatorRole(address account) public onlyRole(REGULATOR_ROLE) {
        grantRole(OPERATOR_ROLE, account);
    }
    
    /**
     * @dev Grants the COMPLIANCE_ROLE to an account
     * @param account Address to receive the role
     * Only ADMIN_ROLE can call this function
     *
     * Compliance officers oversee KYC/AML processes and
     * ensure regulatory adherence across all operations
     */
    function grantComplianceRole(address account) public onlyRole(ADMIN_ROLE) {
        grantRole(COMPLIANCE_ROLE, account);
    }
    
    /**
     * @dev Grants the BANK_PARTNER_ROLE to an account
     * @param account Address to receive the role
     * Only ADMIN_ROLE can call this function
     *
     * Bank partners manage fiat on/off ramps and integrate
     * with the traditional banking system
     */
    function grantBankPartnerRole(address account) public onlyRole(ADMIN_ROLE) {
        grantRole(BANK_PARTNER_ROLE, account);
    }
}