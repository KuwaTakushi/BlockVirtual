// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/pool/virtualPool.sol";
import "../src/virtualGovernance.sol";
import "../src/rwaPriceFeed.sol";
import "../src/rwaToken.sol";
import "../src/library/Errors.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VirtualPoolTest is Test {
    // Test accounts
    address public admin = address(1);
    address public operator = address(2);
    address public feeManager = address(3);
    address public user1 = address(4);
    address public user2 = address(5);
    address public nonKycUser = address(6);
    address public blacklistedUser = address(7);
    address public feeCollector = address(8);
    
    // Contracts and proxies
    VirtualPool public poolImpl;
    ERC1967Proxy public poolProxy;
    VirtualPool public pool;
    
    BlockVirtualGovernance public governanceImpl;
    ERC1967Proxy public governanceProxy;
    BlockVirtualGovernance public governance;
    
    BlockVirtualPriceFeed public priceFeedImpl;
    BlockVirtualPriceFeed public priceFeed;
    
    // Token contracts
    RwaToken public sgdTokenImpl;
    ERC1967Proxy public sgdTokenProxy;
    RwaToken public sgdToken;
    
    RwaToken public usdTokenImpl;
    ERC1967Proxy public usdTokenProxy;
    RwaToken public usdToken;
    
    // Constants
    uint256 public constant SINGAPORE_COUNTRY_CODE = 702;
    uint256 public constant KYC_EXPIRY = 365 days;
    uint256 public constant INITIAL_MINT = 1000000 * 10**18; // 1M tokens
    uint256 public constant SGD_USD_PRICE = 0.75 * 10**18; // 1 SGD = 0.75 USD
    uint256 public constant USD_PRICE = 1 * 10**18; // 1 USD = 1 USD (base price)
    
    function setUp() public {
        // Deploy implementations
        governanceImpl = new BlockVirtualGovernance();
        poolImpl = new VirtualPool();
        priceFeedImpl = new BlockVirtualPriceFeed();
        sgdTokenImpl = new RwaToken();
        usdTokenImpl = new RwaToken();
        
        // Deploy governance proxy and initialize
        governanceProxy = new ERC1967Proxy(
            address(governanceImpl),
            abi.encodeWithSelector(BlockVirtualGovernance.initialize.selector)
        );
        governance = BlockVirtualGovernance(address(governanceProxy));
        
        // Set up governance roles
        vm.startPrank(address(this));
        governance.setupRoleAdmins();
        governance.grantRole(governance.ADMIN_ROLE(), admin);
        governance.grantRole(governance.REGULATOR_ROLE(), operator);
        vm.stopPrank();
        
        // 按照层级关系授予OPERATOR_ROLE
        vm.startPrank(operator); // 操作者有REGULATOR_ROLE，可以授予OPERATOR_ROLE
        governance.grantOperatorRole(operator);
        vm.stopPrank();
        
        // Add supported country code
        vm.prank(admin);
        governance.addSupportedCountryCode(SINGAPORE_COUNTRY_CODE);
        
        // Deploy pool proxy and initialize
        poolProxy = new ERC1967Proxy(
            address(poolImpl),
            abi.encodeWithSelector(VirtualPool.initialize.selector, address(governanceProxy))
        );
        pool = VirtualPool(address(poolProxy));
        
        // Deploy token proxies and initialize
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
        sgdToken = RwaToken(address(sgdTokenProxy));
        
        usdTokenProxy = new ERC1967Proxy(
            address(usdTokenImpl),
            abi.encodeWithSelector(
                RwaToken.initialize.selector,
                "US Dollar",
                "USD",
                address(governanceProxy),
                SINGAPORE_COUNTRY_CODE
            )
        );
        usdToken = RwaToken(address(usdTokenProxy));
        
        // Initialize price feed
        priceFeed = new BlockVirtualPriceFeed();
        
        // Register and activate the pool
        vm.startPrank(admin);
        governance.registerPool(address(pool));
        governance.activatePool(address(pool));
        vm.stopPrank();
        
        // 为所有账户和合约注册KYC
        vm.startPrank(operator);
        // 用户账户
        governance.registerKYCUser(user1, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(user2, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        // 不要为nonKycUser注册KYC，以便测试
        // governance.registerKYCUser(nonKycUser, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(blacklistedUser, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(feeCollector, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(admin, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(feeManager, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(operator, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        
        // 合约地址
        governance.registerKYCUser(address(this), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(governanceProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(pool), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(poolProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(sgdToken), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(sgdTokenProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(usdToken), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(usdTokenProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(priceFeed), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        vm.stopPrank();
        
        // Verify all important addresses have KYC status
        assertTrue(governance.getKycStatus(user1), "User1 should have valid KYC");
        assertTrue(governance.getKycStatus(user2), "User2 should have valid KYC");
        assertTrue(governance.getKycStatus(feeCollector), "FeeCollector should have valid KYC");
        assertTrue(governance.getKycStatus(address(poolProxy)), "Pool proxy should have valid KYC");
        assertTrue(governance.getKycStatus(address(sgdTokenProxy)), "SGD token proxy should have valid KYC");
        assertTrue(governance.getKycStatus(address(usdTokenProxy)), "USD token proxy should have valid KYC");
        
        // Verify nonKycUser does not have KYC
        assertFalse(governance.getKycStatus(nonKycUser), "Non-KYC user should not have KYC");
        
        // Set up pool roles
        vm.startPrank(address(this));
        pool.grantRole(pool.ADMIN_ROLE(), admin);
        pool.grantRole(pool.FEE_MANAGER_ROLE(), feeManager);
        pool.grantRole(pool.OPERATOR_ROLE(), operator);
        vm.stopPrank();
        
        // Set up price feed roles
        vm.startPrank(address(this));
        priceFeed.grantRole(priceFeed.ADMIN_ROLE(), admin);
        priceFeed.grantRole(priceFeed.PRICE_UPDATER_ROLE(), operator);
        vm.stopPrank();
        
        // Set up price feed for pool
        vm.prank(admin);
        pool.setPriceFeed(address(priceFeed));
        
        // Register tokens in price feed
        vm.startPrank(admin);
        priceFeed.registerToken(address(sgdToken));
        priceFeed.registerToken(address(usdToken));
        vm.stopPrank();
        
        // Update prices
        vm.startPrank(operator);
        priceFeed.updatePrice(address(sgdToken), SGD_USD_PRICE);
        priceFeed.updatePrice(address(usdToken), USD_PRICE);
        vm.stopPrank();
        
        // Add supported tokens to pool
        vm.startPrank(admin);
        pool.addSupportedToken(address(sgdToken));
        pool.addSupportedToken(address(usdToken));
        vm.stopPrank();
        
        // Create token pair
        vm.prank(admin);
        pool.createPair(address(sgdToken), address(usdToken));
        
        // Mint initial tokens to test users
        vm.startPrank(address(governanceProxy));
        sgdToken.mintRwa(user1, INITIAL_MINT);
        sgdToken.mintRwa(user2, INITIAL_MINT);
        usdToken.mintRwa(user1, INITIAL_MINT);
        usdToken.mintRwa(user2, INITIAL_MINT);
        vm.stopPrank();
        
        // Set fee collector
        vm.prank(feeManager);
        pool.setFeeCollector(feeCollector);
    }
    
    // Test token pair creation
    function test_PairCreation() public {
        // Create new token implementations for this test
        RwaToken hkdTokenImpl = new RwaToken();
        ERC1967Proxy hkdTokenProxy = new ERC1967Proxy(
            address(hkdTokenImpl),
            abi.encodeWithSelector(
                RwaToken.initialize.selector,
                "Hong Kong Dollar",
                "HKD",
                address(governanceProxy),
                SINGAPORE_COUNTRY_CODE
            )
        );
        RwaToken hkdToken = RwaToken(address(hkdTokenProxy));
        
        // Add supported token
        vm.prank(admin);
        pool.addSupportedToken(address(hkdToken));
        
        // Create new pair
        vm.prank(admin);
        address pairToken = pool.createPair(address(sgdToken), address(hkdToken));
        
        // Verify pair exists
        assertTrue(pairToken != address(0));
        assertEq(pool.getPair(address(sgdToken), address(hkdToken)), pairToken);
        assertEq(pool.getPair(address(hkdToken), address(sgdToken)), pairToken);
        
        // Verify pair count
        assertEq(pool.allPairsLength(), 2);
    }
    
    // Test pair creation fails for unsupported token
    function test_PairCreation_UnsupportedToken() public {
        address randomToken = address(100);
        
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnsupportedToken.selector));
        pool.createPair(address(sgdToken), randomToken);
    }
    
    // Test pair creation fails for same token
    function test_PairCreation_SameToken() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidTokenPair.selector));
        pool.createPair(address(sgdToken), address(sgdToken));
    }
    
    // Test adding liquidity
    function test_AddLiquidity() public {
        uint256 sgdAmount = 1000 * 10**18;
        uint256 usdAmount = 750 * 10**18;
        
        // Verify KYC status is active for users
        assertTrue(governance.getKycStatus(user1), "User1 should have valid KYC");
        assertTrue(governance.isFromSupportedCountry(user1), "User1 should be from supported country");
        
        // Approve tokens
        vm.startPrank(user1);
        sgdToken.approve(address(pool), sgdAmount);
        usdToken.approve(address(pool), usdAmount);
        
        // Add liquidity
        (uint256 sgdUsed, uint256 usdUsed, uint256 liquidity) = pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            sgdAmount,
            usdAmount,
            0, // Min amounts
            0
        );
        vm.stopPrank();
        
        // Verify used amounts
        assertEq(sgdUsed, sgdAmount);
        assertEq(usdUsed, usdAmount);
        assertTrue(liquidity > 0);
        
        // Check reserves
        (uint256 reserveSgd, uint256 reserveUsd) = pool.getReserves(address(sgdToken), address(usdToken));
        assertEq(reserveSgd, sgdAmount);
        assertEq(reserveUsd, usdAmount);
    }
    
    // Test adding liquidity fails for non-KYC user
    function test_AddLiquidity_NonKYC() public {
        uint256 sgdAmount = 1000 * 10**18;
        uint256 usdAmount = 750 * 10**18;
        
        // Mint tokens to non-KYC user (this would normally not be possible through regular means)
        vm.startPrank(address(governanceProxy));
        sgdToken.mintRwa(nonKycUser, INITIAL_MINT);
        usdToken.mintRwa(nonKycUser, INITIAL_MINT);
        vm.stopPrank();
        
        // Verify nonKycUser doesn't have KYC status
        assertFalse(governance.getKycStatus(nonKycUser), "Non-KYC user should not have KYC");
        
        // Approve tokens
        vm.startPrank(nonKycUser);
        sgdToken.approve(address(pool), sgdAmount);
        usdToken.approve(address(pool), usdAmount);
        
        // Attempt to add liquidity - should fail with KYCNotVerified
        vm.expectRevert(abi.encodeWithSelector(Errors.KYCNotVerified.selector, nonKycUser));
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            sgdAmount,
            usdAmount,
            0,
            0
        );
        vm.stopPrank();
    }
    
    // Test adding liquidity with slippage protection
    function test_AddLiquidity_Slippage() public {
        // First add initial liquidity
        uint256 initialSgd = 1000 * 10**18;
        uint256 initialUsd = 750 * 10**18;
        
        // Verify KYC status is active for users
        assertTrue(governance.getKycStatus(user1), "User1 should have valid KYC");
        assertTrue(governance.isFromSupportedCountry(user1), "User1 should be from supported country");
        assertTrue(governance.getKycStatus(user2), "User2 should have valid KYC");
        assertTrue(governance.isFromSupportedCountry(user2), "User2 should be from supported country");
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        vm.stopPrank();
        
        // Now try to add more liquidity with imbalanced amounts
        uint256 moreSgd = 500 * 10**18;
        uint256 moreUsd = 400 * 10**18; // Intentionally imbalanced
        uint256 minUsdRequired = 375 * 10**18; // 500 * 0.75 = 375
        
        vm.startPrank(user2);
        sgdToken.approve(address(pool), moreSgd);
        usdToken.approve(address(pool), moreUsd);
        
        // Should fail due to slippage
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientAmount.selector));
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            moreSgd,
            moreUsd,
            moreSgd, // Min SGD
            moreUsd  // Min USD - will fail since actual used will be less
        );
        
        // Should succeed with appropriate min amount
        (uint256 sgdUsed, uint256 usdUsed, uint256 liquidity) = pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            moreSgd,
            moreUsd,
            0,           // Min SGD
            minUsdRequired  // Min USD
        );
        vm.stopPrank();
        
        // Should use all SGD but less USD due to proportional amounts
        assertEq(sgdUsed, moreSgd);
        assertTrue(usdUsed < moreUsd);
        assertTrue(usdUsed >= minUsdRequired);
    }
    
    // Test swap functionality
    function test_Swap() public {
        // First add liquidity
        uint256 initialSgd = 10000 * 10**18;
        uint256 initialUsd = 7500 * 10**18;
        
        // Verify KYC status is active for users
        assertTrue(governance.getKycStatus(user1), "User1 should have valid KYC");
        assertTrue(governance.getKycStatus(user2), "User2 should have valid KYC");
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        vm.stopPrank();
        
        // Now perform a swap
        uint256 swapSgdAmount = 100 * 10**18;
        uint256 minUsdOut = 70 * 10**18; // Slightly less than expected to account for fees
        
        uint256 user2UsdBefore = usdToken.balanceOf(user2);
        
        vm.startPrank(user2);
        sgdToken.approve(address(pool), swapSgdAmount);
        uint256 usdReceived = pool.swap(
            address(sgdToken),
            address(usdToken),
            swapSgdAmount,
            minUsdOut
        );
        vm.stopPrank();
        
        // Verify swap outcome
        uint256 user2UsdAfter = usdToken.balanceOf(user2);
        assertEq(user2UsdAfter - user2UsdBefore, usdReceived);
        assertTrue(usdReceived >= minUsdOut);
        
        // Check fee collector received fees
        uint256 swapFee = (swapSgdAmount * pool.swapFee()) / 10000;
        assertEq(sgdToken.balanceOf(feeCollector), swapFee);
    }
    
    // Test swap fails for blacklisted user
    function test_Swap_BlacklistedUser() public {
        // First add liquidity
        uint256 initialSgd = 10000 * 10**18;
        uint256 initialUsd = 7500 * 10**18;
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        vm.stopPrank();
        
        // Add KYC for blacklisted user
        vm.prank(operator);
        governance.registerKYCUser(blacklistedUser, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        
        // Mint tokens to blacklisted user
        vm.startPrank(address(governanceProxy));
        sgdToken.mintRwa(blacklistedUser, INITIAL_MINT);
        usdToken.mintRwa(blacklistedUser, INITIAL_MINT);
        vm.stopPrank();
        
        // Add user to blacklist
        vm.prank(operator);
        governance.addBlacklisted(address(sgdToken), blacklistedUser);
        
        // Verify user is blacklisted
        assertTrue(governance.isBlacklisted(address(sgdToken), blacklistedUser), "User should be blacklisted");
        
        // Try to swap
        uint256 swapSgdAmount = 100 * 10**18;
        vm.startPrank(blacklistedUser);
        sgdToken.approve(address(pool), swapSgdAmount);
        
        vm.expectRevert(abi.encodeWithSelector(Errors.Blacklisted.selector, blacklistedUser));
        pool.swap(
            address(sgdToken),
            address(usdToken),
            swapSgdAmount,
            0
        );
        vm.stopPrank();
    }
    
    // Test removing liquidity
    function test_RemoveLiquidity() public {
        // First add liquidity
        uint256 initialSgd = 1000 * 10**18;
        uint256 initialUsd = 750 * 10**18;
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        (,,uint256 liquidity) = pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        
        // Get balances before removal
        uint256 sgdBefore = sgdToken.balanceOf(user1);
        uint256 usdBefore = usdToken.balanceOf(user1);
        
        // Remove half the liquidity
        uint256 liquidityToRemove = liquidity / 2;
        (uint256 sgdReceived, uint256 usdReceived) = pool.removeLiquidity(
            address(sgdToken),
            address(usdToken),
            liquidityToRemove,
            0, // Min amounts
            0
        );
        vm.stopPrank();
        
        // Verify received amounts
        uint256 sgdAfter = sgdToken.balanceOf(user1);
        uint256 usdAfter = usdToken.balanceOf(user1);
        assertEq(sgdAfter - sgdBefore, sgdReceived);
        assertEq(usdAfter - usdBefore, usdReceived);
        
        // Should receive proportional amounts
        assertApproxEqRel(sgdReceived, initialSgd / 2, 1e16); // Allow for small rounding errors
        assertApproxEqRel(usdReceived, initialUsd / 2, 1e16);
        
        // Check updated reserves
        (uint256 reserveSgd, uint256 reserveUsd) = pool.getReserves(address(sgdToken), address(usdToken));
        assertApproxEqRel(reserveSgd, initialSgd / 2, 1e16);
        assertApproxEqRel(reserveUsd, initialUsd / 2, 1e16);
    }
    
    // Test emergency withdrawal
    function test_EmergencyWithdraw() public {
        // First add liquidity
        uint256 initialSgd = 1000 * 10**18;
        uint256 initialUsd = 750 * 10**18;
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        vm.stopPrank();
        
        // Check initial SGD balance of contract
        uint256 initialPoolBalance = sgdToken.balanceOf(address(pool));
        assertEq(initialPoolBalance, initialSgd, "Initial pool balance should match added liquidity");
        
        // Emergency withdraw half of SGD
        uint256 withdrawAmount = initialSgd / 2;
        uint256 adminBalanceBefore = sgdToken.balanceOf(admin);
        
        vm.prank(admin);
        pool.emergencyWithdraw(address(sgdToken), withdrawAmount);
        
        // Verify withdrawal to admin
        uint256 adminBalanceAfter = sgdToken.balanceOf(admin);
        assertEq(adminBalanceAfter - adminBalanceBefore, withdrawAmount, "Admin should receive withdraw amount");
        
        // Check updated pool balance
        uint256 finalPoolBalance = sgdToken.balanceOf(address(pool));
        assertEq(finalPoolBalance, initialPoolBalance - withdrawAmount, "Pool balance should be reduced by withdrawn amount");
    }
    
    // Test pause functionality
    function test_Pause() public {
        // First add liquidity
        uint256 initialSgd = 10000 * 10**18;
        uint256 initialUsd = 7500 * 10**18;
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        vm.stopPrank();
        
        // Pause the pool
        vm.prank(admin);
        pool.pause();
        
        // Try to swap - should fail
        uint256 swapSgdAmount = 100 * 10**18;
        vm.startPrank(user2);
        sgdToken.approve(address(pool), swapSgdAmount);
        
        // 使用正确的错误类型 EnforcedPause
        vm.expectRevert(bytes4(0xd93c0665)); // EnforcedPause 错误选择器
        pool.swap(
            address(sgdToken),
            address(usdToken),
            swapSgdAmount,
            0
        );
        vm.stopPrank();
        
        // Unpause the pool
        vm.prank(admin);
        pool.unpause();
        
        // Swap should succeed now
        vm.startPrank(user2);
        pool.swap(
            address(sgdToken),
            address(usdToken),
            swapSgdAmount,
            0
        );
        vm.stopPrank();
    }
    
    // Test fee management
    function test_FeeManagement() public {
        // Change fees
        uint256 newSwapFee = 50; // 0.5%
        uint256 newLiquidityFee = 10; // 0.1%
        
        vm.startPrank(feeManager);
        pool.setSwapFee(newSwapFee);
        pool.setLiquidityFee(newLiquidityFee);
        vm.stopPrank();
        
        // Verify new fees
        assertEq(pool.swapFee(), newSwapFee);
        assertEq(pool.liquidityFee(), newLiquidityFee);
        
        // Test with new fees
        uint256 initialSgd = 10000 * 10**18;
        uint256 initialUsd = 7500 * 10**18;
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        vm.stopPrank();
        
        // Swap with new fee
        uint256 swapSgdAmount = 100 * 10**18;
        vm.startPrank(user2);
        sgdToken.approve(address(pool), swapSgdAmount);
        pool.swap(
            address(sgdToken),
            address(usdToken),
            swapSgdAmount,
            0
        );
        vm.stopPrank();
        
        // Check fee collector received correct amount
        uint256 expectedFee = (swapSgdAmount * newSwapFee) / 10000;
        assertEq(sgdToken.balanceOf(feeCollector), expectedFee);
    }
    
    // Test quote calculation
    function test_Quote() public {
        uint256 reserveIn = 10000 * 10**18;
        uint256 reserveOut = 7500 * 10**18;
        uint256 amountIn = 100 * 10**18;
        
        uint256 amountOut = pool.quote(amountIn, reserveIn, reserveOut);
        
        // Expected: (7500 * (100 * 0.997)) / (10000 + (100 * 0.997))
        // = 7500 * 99.7 / 10099.7 ≈ 74.7 tokens
        
        uint256 feeAmount = (amountIn * 30) / 10000; // 0.3% fee
        uint256 amountInWithFee = amountIn - feeAmount;
        uint256 expected = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        
        assertEq(amountOut, expected);
    }
    
    // Test getAmountOut matches actual swap results
    function test_GetAmountOut() public {
        // First add liquidity
        uint256 initialSgd = 10000 * 10**18;
        uint256 initialUsd = 7500 * 10**18;
        
        vm.startPrank(user1);
        sgdToken.approve(address(pool), initialSgd);
        usdToken.approve(address(pool), initialUsd);
        pool.addLiquidity(
            address(sgdToken),
            address(usdToken),
            initialSgd,
            initialUsd,
            0,
            0
        );
        vm.stopPrank();
        
        // Get estimated output amount
        uint256 swapSgdAmount = 100 * 10**18;
        uint256 estimatedUsd = pool.getAmountOut(
            address(sgdToken),
            address(usdToken),
            swapSgdAmount
        );
        
        // Perform actual swap
        vm.startPrank(user2);
        sgdToken.approve(address(pool), swapSgdAmount);
        uint256 actualUsd = pool.swap(
            address(sgdToken),
            address(usdToken),
            swapSgdAmount,
            0
        );
        vm.stopPrank();
        
        // Estimates should match actual results
        assertEq(estimatedUsd, actualUsd);
    }   
}