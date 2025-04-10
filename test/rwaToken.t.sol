// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/virtualGovernance.sol";
import "../src/rwaToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RwaTokenTest is Test {
    // Test accounts
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    address public nonKycUser = address(6);
    address public foreignUser = address(7);
    address public blacklistedUser = address(8);
    
    // Proxy and implementation contracts
    ERC1967Proxy public governanceProxy;
    ERC1967Proxy public sgdTokenProxy;
    
    BlockVirtualGovernance public governanceImpl;
    RwaToken public sgdTokenImpl;
    
    // Constants
    uint256 public constant SINGAPORE_COUNTRY_CODE = 702;
    uint256 public constant FOREIGN_COUNTRY_CODE = 840; // USA
    uint256 public constant KYC_EXPIRY = 365 days;
    
    function setUp() public {
        // Deploy implementation contracts
        governanceImpl = new BlockVirtualGovernance();
        sgdTokenImpl = new RwaToken();
        
        // Deploy and initialize governance proxy
        governanceProxy = new ERC1967Proxy(
            address(governanceImpl),
            abi.encodeWithSelector(BlockVirtualGovernance.initialize.selector)
        );
        
        // Set up governance contract permissions
        vm.startPrank(address(this));
        BlockVirtualGovernance(address(governanceProxy)).setupRoleAdmins();
        
        BlockVirtualGovernance(address(governanceProxy)).grantRole(
            keccak256("DEFAULT_ADMIN_ROLE"),
            admin
        );
        BlockVirtualGovernance(address(governanceProxy)).grantRole(
            keccak256("ADMIN_ROLE"),
            admin
        );
        BlockVirtualGovernance(address(governanceProxy)).grantRole(
            keccak256("REGULATOR_ROLE"),
            operator
        );
        vm.stopPrank();
        
        // Deploy SGD token proxy
        sgdTokenProxy = new ERC1967Proxy(
            address(sgdTokenImpl),
            abi.encodeWithSelector(
                RwaToken.initialize.selector,
                "Singapore Dollar",
                "SGD",
                address(governanceProxy),
                SINGAPORE_COUNTRY_CODE
            )
        );
        
        // Add supported country code
        vm.prank(admin);
        BlockVirtualGovernance(address(governanceProxy)).addSupportedCountryCode(SINGAPORE_COUNTRY_CODE);
        
        // Set up KYC for test users
        vm.startPrank(operator);
        
        // Register KYC for Singapore users
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            user1, 
            block.timestamp + KYC_EXPIRY, 
            SINGAPORE_COUNTRY_CODE
        );
        
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            user2, 
            block.timestamp + KYC_EXPIRY, 
            SINGAPORE_COUNTRY_CODE
        );
        
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            user3, 
            block.timestamp + KYC_EXPIRY, 
            SINGAPORE_COUNTRY_CODE
        );
        
        // Register KYC for foreign user
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            foreignUser, 
            block.timestamp + KYC_EXPIRY, 
            FOREIGN_COUNTRY_CODE
        );
        
        // Add a user to blacklist
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            blacklistedUser
        );
        
        vm.stopPrank();
    }
    
    // Test token initialization is correct
    function test_TokenInitialization() public {
        // Verify token initialization is correct
        assertEq(RwaToken(address(sgdTokenProxy)).name(), "Singapore Dollar");
        assertEq(RwaToken(address(sgdTokenProxy)).symbol(), "SGD");
        assertEq(RwaToken(address(sgdTokenProxy)).blockVirtualGovernance(), address(governanceProxy));
        assertEq(RwaToken(address(sgdTokenProxy)).supportedCountryCode(), SINGAPORE_COUNTRY_CODE);
    }
    
    // Test minting RWA tokens functionality
    function test_MintRwa() public {
        // Only governance contract can mint tokens
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Verify balance
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 1000 ether);
    }
    
    // Test unauthorized account trying to mint tokens
    function test_MintRwa_Unauthorized() public {
        // Non-governance contract cannot mint tokens
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedRole.selector, admin));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
    }
    
    // Test minting to blacklisted user fails
    function test_MintRwa_BlacklistedUser() public {
        // Minting to blacklisted user should fail
        vm.prank(address(governanceProxy));
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, blacklistedUser));
        RwaToken(address(sgdTokenProxy)).mintRwa(blacklistedUser, 1000 ether);
    }
    
    // Test burning RWA tokens functionality
    function test_BurnRwa() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Then burn some tokens
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).burnRwa(user1, 500 ether);
        
        // Verify balance
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 500 ether);
    }
    
    // Test unauthorized account trying to burn tokens
    function test_BurnRwa_Unauthorized() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Non-governance contract cannot burn tokens
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedRole.selector, admin));
        RwaToken(address(sgdTokenProxy)).burnRwa(user1, 500 ether);
    }
    
    // Test burning from blacklisted user fails
    function test_BurnRwa_BlacklistedUser() public {
        // This test simulates a user getting tokens, then being blacklisted, then attempting to burn tokens
        
        // Set up a temporary user
        address tempUser = address(100);
        
        // Register KYC for temporary user
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            tempUser, 
            block.timestamp + KYC_EXPIRY, 
            SINGAPORE_COUNTRY_CODE
        );
        
        // Mint tokens to temporary user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(tempUser, 1000 ether);
        
        // Add user to blacklist
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            tempUser
        );
        
        // Attempting to burn tokens from blacklisted user should fail
        vm.prank(address(governanceProxy));
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, tempUser));
        RwaToken(address(sgdTokenProxy)).burnRwa(tempUser, 500 ether);
    }
    
    // Test transfer functionality
    function test_Transfer_Successful() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Transfer should be successful
        vm.prank(user1);
        bool success = RwaToken(address(sgdTokenProxy)).transfer(user2, 400 ether);
        
        // Verify results
        assertTrue(success);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 600 ether);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user2), 400 ether);
    }
    
    // Test transfer to user without KYC fails
    function test_Transfer_NoKyc() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Attempting to transfer to user without KYC should fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedKycStatus.selector));
        RwaToken(address(sgdTokenProxy)).transfer(nonKycUser, 400 ether);
    }
    
    // Test transfer to user from unsupported country fails
    function test_Transfer_UnsupportedCountry() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Attempting to transfer to user from unsupported country should fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedCountryUser.selector));
        RwaToken(address(sgdTokenProxy)).transfer(foreignUser, 400 ether);
    }
    
    // Test transfer involving blacklisted user fails
    function test_Transfer_Blacklisted() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Transfer to blacklisted user should fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, blacklistedUser));
        RwaToken(address(sgdTokenProxy)).transfer(blacklistedUser, 400 ether);
        
        // Add sender to blacklist
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // Blacklisted user attempting to transfer should also fail
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, user1));
        RwaToken(address(sgdTokenProxy)).transfer(user2, 400 ether);
    }
    
    // Test transferFrom functionality is successful
    function test_TransferFrom_Successful() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Approve user2 to spend some tokens
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // User2 executes transferFrom
        vm.prank(user2);
        bool success = RwaToken(address(sgdTokenProxy)).transferFrom(user1, user3, 300 ether);
        
        // Verify results
        assertTrue(success);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 700 ether);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user3), 300 ether);
        assertEq(RwaToken(address(sgdTokenProxy)).allowance(user1, user2), 200 ether);
    }
    
    // Test transferFrom to user without KYC fails
    function test_TransferFrom_NoKyc() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Approve user2 to spend some tokens
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // Attempting to transfer to user without KYC should fail
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedKycStatus.selector));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, nonKycUser, 300 ether);
    }
    
    // Test transferFrom to user from unsupported country fails
    function test_TransferFrom_UnsupportedCountry() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Approve user2 to spend some tokens
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // Attempting to transfer to user from unsupported country should fail
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedCountryUser.selector));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, foreignUser, 300 ether);
    }
    
    // Test transferFrom involving blacklisted user fails
    function test_TransferFrom_Blacklisted() public {
        // First mint tokens to user
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // Approve user2 to spend some tokens
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // Transfer to blacklisted user should fail
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, blacklistedUser));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, blacklistedUser, 300 ether);
        
        // Add source address to blacklist
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // Using blacklisted user as source address should also fail
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, user1));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, user3, 300 ether);
    }
    
    // Test compliance check functionality
    function test_CheckCompliance() public {
        // Test compliance check
        bool compliant = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, user2);
        assertTrue(compliant);
        
        // Non-compliant cases
        bool notCompliant1 = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, nonKycUser);
        assertFalse(notCompliant1);
        
        bool notCompliant2 = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, foreignUser);
        assertFalse(notCompliant2);
        
        bool notCompliant3 = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, blacklistedUser);
        assertFalse(notCompliant3);
    }
    
    // Test blacklist check functionality
    function test_IsBlacklisted() public {
        // Check blacklist status
        assertTrue(RwaToken(address(sgdTokenProxy)).isBlacklisted(blacklistedUser));
        assertFalse(RwaToken(address(sgdTokenProxy)).isBlacklisted(user1));
        
        // Add user to blacklist
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // Verify user is now blacklisted
        assertTrue(RwaToken(address(sgdTokenProxy)).isBlacklisted(user1));
        
        // Remove user from blacklist
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).removeBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // Verify user is now not blacklisted
        assertFalse(RwaToken(address(sgdTokenProxy)).isBlacklisted(user1));
    }
} 