// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/rwaPriceFeed.sol";
import "../src/library/Errors.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceFeedTest is Test {
    // Test accounts
    address public admin = address(1);
    address public priceUpdater = address(2);
    address public unauthorizedUser = address(3);
    
    // Contract instances
    BlockVirtualPriceFeed public priceFeed;
    
    // Mock token addresses
    address public sgdToken = address(10);
    address public usdToken = address(11);
    address public rwaToken = address(12);
    
    // Constants
    uint256 public constant SGD_USD_PRICE = 0.75 * 1e18; // 1 SGD = 0.75 USD
    uint256 public constant USD_SGD_PRICE = 1.33 * 1e18; // 1 USD = 1.33 SGD
    uint256 public constant RWA_USD_PRICE = 100 * 1e18;  // 1 RWA = 100 USD
    
    function setUp() public {
        vm.startPrank(address(this));
        
        // Deploy price feed contract
        priceFeed = new BlockVirtualPriceFeed();
        
        // Set up roles
        priceFeed.grantRole(priceFeed.ADMIN_ROLE(), admin);
        priceFeed.grantRole(priceFeed.PRICE_UPDATER_ROLE(), priceUpdater);
        
        // Important: Revoke deployer permissions to ensure correct permission testing
        priceFeed.revokeRole(priceFeed.ADMIN_ROLE(), address(this));
        priceFeed.revokeRole(priceFeed.PRICE_UPDATER_ROLE(), address(this));
        
        vm.stopPrank();
    }
    
    // Test if role assignment is correct
    function test_RoleAssignment() public {
        bytes32 defaultAdminRole = 0x00;
        assertTrue(priceFeed.hasRole(defaultAdminRole, address(this)));
        assertTrue(priceFeed.hasRole(priceFeed.ADMIN_ROLE(), admin));
        assertTrue(priceFeed.hasRole(priceFeed.PRICE_UPDATER_ROLE(), priceUpdater));
        assertFalse(priceFeed.hasRole(priceFeed.ADMIN_ROLE(), unauthorizedUser));
        assertFalse(priceFeed.hasRole(priceFeed.PRICE_UPDATER_ROLE(), unauthorizedUser));
    }
    
    // Test admin registering new token
    function test_RegisterToken() public {
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // Verify token is registered
        assertTrue(priceFeed.isTokenRegistered(sgdToken));
        
        // Verify registered token list
        address[] memory tokens = priceFeed.getAllTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], sgdToken);
    }
    
    // Test unauthorized user failing to register token
    function test_RegisterToken_Unauthorized() public {
        bytes memory revertData = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorizedUser,
            priceFeed.ADMIN_ROLE()
        );
        
        vm.expectRevert(revertData);
        vm.prank(unauthorizedUser);
        priceFeed.registerToken(sgdToken);
    }
    
    // Test registering zero address failing
    function test_RegisterToken_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        priceFeed.registerToken(address(0));
    }
    
    // Test registering an already registered token fails
    function test_RegisterToken_AlreadyRegistered() public {
        // Register once
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // Registering again should fail
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenAlreadyRegistered.selector));
        priceFeed.registerToken(sgdToken);
    }
    
    // Test price updater updating price
    function test_UpdatePrice() public {
        // First register the token
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // Update price
        vm.prank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
        
        // Verify price update succeeded
        assertEq(priceFeed.getLatestPrice(sgdToken), SGD_USD_PRICE);
        
        // Verify timestamp is not zero
        assertTrue(priceFeed.getPriceTimestamp(sgdToken) > 0);
    }
    
    // Test updating price for unregistered token fails
    function test_UpdatePrice_NotRegistered() public {
        // Try to update price for unregistered token
        vm.prank(priceUpdater);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAddress.selector));
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
    }
    
    // Test unauthorized user attempting to update price fails
    function test_UpdatePrice_Unauthorized() public {
        // First register the token
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        bytes memory revertData = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorizedUser,
            priceFeed.PRICE_UPDATER_ROLE()
        );
        
        // Unauthorized user attempts to update price
        vm.expectRevert(revertData);
        vm.prank(unauthorizedUser);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
    }
    
    // Test updating price for zero address fails
    function test_UpdatePrice_ZeroAddress() public {
        vm.prank(priceUpdater);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        priceFeed.updatePrice(address(0), SGD_USD_PRICE);
    }
    
    // Test updating price to zero fails
    function test_UpdatePrice_ZeroPrice() public {
        // First register the token
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // Try to update price to zero
        vm.prank(priceUpdater);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector));
        priceFeed.updatePrice(sgdToken, 0);
    }
    
    // Test getting price for token without set price fails
    function test_GetLatestPrice_NotAvailable() public {
        // Register token but don't set price
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // Trying to get price should fail
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceNotAvailable.selector));
        priceFeed.getLatestPrice(sgdToken);
    }
    
    // Test getting price for unregistered token fails
    function test_GetLatestPrice_NotRegistered() public {
        // Try to get price for unregistered token
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceNotAvailable.selector));
        priceFeed.getLatestPrice(usdToken);
    }
    
    // Test calculating conversion between tokens
    function test_CalculateConversion() public {
        // Register two tokens
        vm.startPrank(admin);
        priceFeed.registerToken(sgdToken);
        priceFeed.registerToken(usdToken);
        vm.stopPrank();
        
        // Set prices
        vm.startPrank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
        priceFeed.updatePrice(usdToken, 1e18); // 1 USD = 1 USD (base price)
        vm.stopPrank();
        
        // Calculate 100 SGD conversion to USD
        uint256 sgdAmount = 100 * 1e18;
        uint256 usdAmount = priceFeed.calculateConversion(sgdToken, usdToken, sgdAmount);
        
        // 100 SGD * 0.75 = 75 USD
        assertEq(usdAmount, 75 * 1e18);
        
        // Calculate conversion for same token
        uint256 sameTokenAmount = priceFeed.calculateConversion(sgdToken, sgdToken, sgdAmount);
        assertEq(sameTokenAmount, sgdAmount); // Should return same amount
    }
    
    // Test complex multi-token conversion
    function test_MultiTokenConversion() public {
        // Register three tokens
        vm.startPrank(admin);
        priceFeed.registerToken(sgdToken);
        priceFeed.registerToken(usdToken);
        priceFeed.registerToken(rwaToken);
        vm.stopPrank();
        
        // Set prices
        vm.startPrank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE); // 1 SGD = 0.75 USD
        priceFeed.updatePrice(usdToken, 1e18); // 1 USD = 1 USD (base price)
        priceFeed.updatePrice(rwaToken, RWA_USD_PRICE); // 1 RWA = 100 USD
        vm.stopPrank();
        
        // Calculate 1000 SGD conversion to RWA
        uint256 sgdAmount = 1000 * 1e18;
        uint256 rwaAmount = priceFeed.calculateConversion(sgdToken, rwaToken, sgdAmount);
        
        // 1000 SGD * 0.75 / 100 = 7.5 RWA
        assertEq(rwaAmount, 75 * 1e17);
        
        // Reverse calculation: 1 RWA to SGD
        uint256 oneRwa = 1e18;
        uint256 sgdFromRwa = priceFeed.calculateConversion(rwaToken, sgdToken, oneRwa);
        
        // 1 RWA * 100 / 0.75 = 133.33... SGD
        assertApproxEqRel(sgdFromRwa, 1333333333333333333e2, 1e15); // Allow small error margin
    }
    
    // Test conversion calculation failing due to missing price information
    function test_CalculateConversion_PriceNotAvailable() public {
        // Register token but don't set price
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // Also register and set price for another token
        vm.prank(admin);
        priceFeed.registerToken(usdToken);
        
        vm.prank(priceUpdater);
        priceFeed.updatePrice(usdToken, 1e18);
        
        // Trying to calculate conversion should fail
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceNotAvailable.selector));
        priceFeed.calculateConversion(sgdToken, usdToken, 100 * 1e18);
    }
    
    // Test querying all registered tokens
    function test_GetAllTokens() public {
        // Initial state should have no registered tokens
        address[] memory initialTokens = priceFeed.getAllTokens();
        assertEq(initialTokens.length, 0);
        
        // Register multiple tokens
        vm.startPrank(admin);
        priceFeed.registerToken(sgdToken);
        priceFeed.registerToken(usdToken);
        priceFeed.registerToken(rwaToken);
        vm.stopPrank();
        
        // Verify registered token list
        address[] memory tokens = priceFeed.getAllTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], sgdToken);
        assertEq(tokens[1], usdToken);
        assertEq(tokens[2], rwaToken);
    }
    
    // Test checking if token is registered
    function test_IsTokenRegistered() public {
        // Initially token is not registered
        assertFalse(priceFeed.isTokenRegistered(sgdToken));
        
        // Register token
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // Verify token is registered
        assertTrue(priceFeed.isTokenRegistered(sgdToken));
        assertFalse(priceFeed.isTokenRegistered(usdToken)); // Other tokens still not registered
    }
    
    // Test price update timestamp
    function test_PriceTimestamp() public {
        // Register and set token price
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        uint256 beforeUpdate = block.timestamp;
        
        // Update price
        vm.prank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
        
        // Get timestamp
        uint256 priceTimestamp = priceFeed.getPriceTimestamp(sgdToken);
        
        // Verify timestamp matches current block time
        assertEq(priceTimestamp, beforeUpdate);
        
        // Unregistered token timestamp should be 0
        assertEq(priceFeed.getPriceTimestamp(usdToken), 0);
    }
} 