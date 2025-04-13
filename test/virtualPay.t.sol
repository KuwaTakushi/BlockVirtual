// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/virtualPay.sol";
import "../src/pool/virtualPool.sol";
import "../src/virtualGovernance.sol";
import "../src/rwaPriceFeed.sol";
import "../src/rwaToken.sol";
import "../src/library/Errors.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VirtualPayTest is Test {
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(4);
    address public user2 = address(5);
    address public nonKycUser = address(6);
    
    VirtualPay public payImpl;
    ERC1967Proxy public payProxy;
    VirtualPay public pay;
    
    VirtualPool public poolImpl;
    ERC1967Proxy public poolProxy;
    VirtualPool public pool;
    
    BlockVirtualGovernance public governanceImpl;
    ERC1967Proxy public governanceProxy;
    BlockVirtualGovernance public governance;
    
    BlockVirtualPriceFeed public priceFeedImpl;
    BlockVirtualPriceFeed public priceFeed;
    
    RwaToken public sgdTokenImpl;
    ERC1967Proxy public sgdTokenProxy;
    RwaToken public sgdToken;
    
    RwaToken public usdTokenImpl;
    ERC1967Proxy public usdTokenProxy;
    RwaToken public usdToken;
    
    uint256 public constant SINGAPORE_COUNTRY_CODE = 702;
    uint256 public constant KYC_EXPIRY = 365 days;
    uint256 public constant INITIAL_MINT = 1000000 * 10**18; // 1M tokens
    uint256 public constant SGD_USD_PRICE = 0.75 * 10**18; // 1 SGD = 0.75 USD
    uint256 public constant USD_PRICE = 1 * 10**18; // 1 USD = 1 USD (base price)
    
    function setUp() public {
        // Deploy implementations
        governanceImpl = new BlockVirtualGovernance();
        poolImpl = new VirtualPool();
        payImpl = new VirtualPay();
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
        
        vm.startPrank(operator);
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
        
        // Deploy pay proxy and initialize
        payProxy = new ERC1967Proxy(
            address(payImpl),
            abi.encodeWithSelector(VirtualPay.initialize.selector, address(poolProxy), address(governanceProxy))
        );
        pay = VirtualPay(address(payProxy));
        
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
        
        vm.startPrank(operator);
        governance.registerKYCUser(user1, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(user2, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(admin, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(operator, block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        
        governance.registerKYCUser(address(this), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(governanceProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(pool), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(poolProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(sgdToken), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(sgdTokenProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(usdToken), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(usdTokenProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(priceFeed), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(pay), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        governance.registerKYCUser(address(payProxy), block.timestamp + KYC_EXPIRY, SINGAPORE_COUNTRY_CODE);
        vm.stopPrank();
        
        // Set up pool roles
        vm.startPrank(address(this));
        pool.grantRole(pool.ADMIN_ROLE(), admin);
        pool.grantRole(pool.OPERATOR_ROLE(), operator);
        vm.stopPrank();
        
        // Set up pay roles
        vm.startPrank(address(this));
        pay.grantRole(pay.ADMIN_ROLE(), admin);
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
    }
    
    // Test process payment
    function test_ProcessPayment() public {
        // First add liquidity to pool
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
        
        // Process payment
        uint256 paymentAmount = 100 * 10**18;
        uint256 minUsdOut = 70 * 10**18;
        
        uint256 user2UsdBefore = usdToken.balanceOf(user2);
        
        vm.startPrank(user1);
        sgdToken.approve(address(pay), paymentAmount);
        uint256 usdReceived = pay.processPayment(
            user2,
            address(sgdToken),
            address(usdToken),
            paymentAmount,
            minUsdOut
        );
        vm.stopPrank();
        
        // Verify payment outcome
        uint256 user2UsdAfter = usdToken.balanceOf(user2);
        assertEq(user2UsdAfter - user2UsdBefore, usdReceived);
        assertTrue(usdReceived >= minUsdOut);
    }
    
    // Test non-KYC user
    function test_NonKYCUser() public {
        // First add liquidity to pool
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
        
        // Mint tokens to non-KYC user
        vm.startPrank(address(governanceProxy));
        sgdToken.mintRwa(nonKycUser, INITIAL_MINT);
        vm.stopPrank();
        
        // Try to make payment - should fail
        uint256 paymentAmount = 100 * 10**18;
        vm.startPrank(nonKycUser);
        sgdToken.approve(address(pay), paymentAmount);
        
        vm.expectRevert(abi.encodeWithSelector(Errors.KYCNotVerified.selector, nonKycUser));
        pay.processPayment(
            user2,
            address(sgdToken),
            address(usdToken),
            paymentAmount,
            0
        );
        vm.stopPrank();
    }
    
    // Test pause functionality
    function test_Pause() public {
        // First add liquidity to pool
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
        
        // Pause the contract
        vm.prank(admin);
        pay.pause();
        
        // Try to make payment - should fail
        uint256 paymentAmount = 100 * 10**18;
        vm.startPrank(user1);
        sgdToken.approve(address(pay), paymentAmount);
        
        vm.expectRevert(bytes4(0xd93c0665)); // EnforcedPause 错误选择器
        pay.processPayment(
            user2,
            address(sgdToken),
            address(usdToken),
            paymentAmount,
            0
        );
        vm.stopPrank();
        
        // Unpause the contract
        vm.prank(admin);
        pay.unpause();
        
        // Payment should succeed now
        vm.startPrank(user1);
        pay.processPayment(
            user2,
            address(sgdToken),
            address(usdToken),
            paymentAmount,
            0
        );
        vm.stopPrank();
    }
}