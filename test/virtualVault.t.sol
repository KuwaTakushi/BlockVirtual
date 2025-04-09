// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/virtualVault.sol";
import "../src/rwaPriceFeed.sol";
import "../src/virtualGovernance.sol";
import "../src/rwaToken.sol";
import "../src/library/Errors.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VirtualVaultTest is Test {
    // 测试账户
    address public admin = address(1);
    address public marketMaker = address(2);
    address public priceUpdater = address(3);
    address public user1 = address(4);
    address public user2 = address(5);
    address public unauthorizedUser = address(6);
    
    // 代理合约和实现合约
    ERC1967Proxy public governanceProxy;
    // 价格预言机不使用代理
    ERC1967Proxy public sgdTokenProxy;
    ERC1967Proxy public usdTokenProxy;
    ERC1967Proxy public sgdVaultProxy;
    ERC1967Proxy public usdVaultProxy;
    
    BlockVirtualGovernance public governanceImpl;
    BlockVirtualPriceFeed public priceFeed; // 直接部署
    RwaToken public sgdTokenImpl;
    RwaToken public usdTokenImpl;
    VirtualVault public sgdVaultImpl;
    VirtualVault public usdVaultImpl;
    
    // 合约实例
    BlockVirtualGovernance public governance;
    RwaToken public sgdToken;
    RwaToken public usdToken;
    VirtualVault public sgdVault;
    VirtualVault public usdVault;
    
    // 常量
    uint256 public constant SINGAPORE_COUNTRY_CODE = 702;
    uint256 public constant KYC_EXPIRY = 365 days;
    uint256 public constant SGD_USD_PRICE = 0.75 * 1e18; // 1 SGD = 0.75 USD
    uint256 public constant USD_SGD_PRICE = 1.33 * 1e18; // 1 USD = 1.33 SGD
    uint256 public constant INITIAL_MINT_AMOUNT = 1000000 * 1e18; // 100万代币初始铸造
    uint256 public constant DEPOSIT_AMOUNT = 10000 * 1e18; // 1万代币存款测试
    
    function setUp() public {
        // 部署实现合约
        governanceImpl = new BlockVirtualGovernance();
        // 直接部署价格预言机
        priceFeed = new BlockVirtualPriceFeed();
        sgdTokenImpl = new RwaToken();
        usdTokenImpl = new RwaToken();
        sgdVaultImpl = new VirtualVault();
        usdVaultImpl = new VirtualVault();
        
        // 部署治理代理
        governanceProxy = new ERC1967Proxy(
            address(governanceImpl),
            abi.encodeWithSelector(BlockVirtualGovernance.initialize.selector)
        );
        governance = BlockVirtualGovernance(address(governanceProxy));
        
        // 设置治理合约权限
        vm.startPrank(address(this));
        governance.setupRoleAdmins();
        governance.grantRole(governance.DEFAULT_ADMIN_ROLE(), admin);
        governance.grantRole(governance.ADMIN_ROLE(), admin);
        governance.grantRole(governance.REGULATOR_ROLE(), admin);
        
        // 添加支持的国家代码 - 添加多个国家以确保覆盖
        governance.addSupportedCountryCode(SINGAPORE_COUNTRY_CODE);
        
        // 添加一个通用的测试国家代码 - 使用虚构值100
        governance.addSupportedCountryCode(100);
        vm.stopPrank();
        
        // 为价格预言机授予权限 - 价格预言机已在构造函数中为部署者授予DEFAULT_ADMIN_ROLE
        vm.startPrank(address(this));
        priceFeed.grantRole(priceFeed.ADMIN_ROLE(), admin);
        priceFeed.grantRole(priceFeed.PRICE_UPDATER_ROLE(), priceUpdater);
        vm.stopPrank();
        
        // 部署代币代理
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
        
        // 部署Vault代理
        sgdVaultProxy = new ERC1967Proxy(
            address(sgdVaultImpl),
            abi.encodeWithSelector(
                VirtualVault.initialize.selector,
                address(governanceProxy),
                address(priceFeed),
                address(sgdTokenProxy),
                "SGD Vault",
                "vSGD"
            )
        );
        sgdVault = VirtualVault(address(sgdVaultProxy));
        
        usdVaultProxy = new ERC1967Proxy(
            address(usdVaultImpl),
            abi.encodeWithSelector(
                VirtualVault.initialize.selector,
                address(governanceProxy),
                address(priceFeed),
                address(usdTokenProxy),
                "USD Vault",
                "vUSD"
            )
        );
        usdVault = VirtualVault(address(usdVaultProxy));
        
        // 为测试用户设置KYC
        vm.startPrank(admin);
        
        // 确保每个地址的countryCode关联被设置，这样isFromSupportedCountry才会返回true
        for (uint i = 1; i <= 20; i++) {
            address user = address(uint160(i));
            
            // 设置KYC
            governance.registerKYCUser(
                user, 
                block.timestamp + KYC_EXPIRY, 
                SINGAPORE_COUNTRY_CODE
            );
            
            // 显式设置国家代码，确保通过isFromSupportedCountry检查
            governance.addSupportedCountryCode(SINGAPORE_COUNTRY_CODE);
        }
        
        vm.stopPrank();
        
        // 在价格预言机中注册代币
        vm.startPrank(admin);
        priceFeed.registerToken(address(sgdToken));
        priceFeed.registerToken(address(usdToken));
        vm.stopPrank();
        
        // 设置代币价格
        vm.startPrank(priceUpdater);
        priceFeed.updatePrice(address(sgdToken), SGD_USD_PRICE);
        priceFeed.updatePrice(address(usdToken), 1e18); // 1 USD = 1 USD (基准价格)
        vm.stopPrank();
        
        // 为Market Maker授予权限
        vm.startPrank(admin);
        sgdVault.addLiquidityProvider(marketMaker);
        usdVault.addLiquidityProvider(marketMaker);
        vm.stopPrank();
        
        // 为测试铸造代币
        vm.startPrank(address(governanceProxy));
        sgdToken.mintRwa(marketMaker, INITIAL_MINT_AMOUNT);
        sgdToken.mintRwa(user1, INITIAL_MINT_AMOUNT);
        sgdToken.mintRwa(user2, INITIAL_MINT_AMOUNT);
        
        usdToken.mintRwa(marketMaker, INITIAL_MINT_AMOUNT);
        usdToken.mintRwa(user1, INITIAL_MINT_AMOUNT);
        usdToken.mintRwa(user2, INITIAL_MINT_AMOUNT);
        vm.stopPrank();
        
        // 为Vault准备初始流动性
        vm.startPrank(marketMaker);
        sgdToken.approve(address(sgdVault), DEPOSIT_AMOUNT);
        sgdVault.deposit(DEPOSIT_AMOUNT);
        
        usdToken.approve(address(usdVault), DEPOSIT_AMOUNT);
        usdVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }
    
    // 测试初始设置是否正确
    function test_InitialSetup() public {
        // 验证代币注册和价格
        assertTrue(priceFeed.isTokenRegistered(address(sgdToken)));
        assertTrue(priceFeed.isTokenRegistered(address(usdToken)));
        assertEq(priceFeed.getLatestPrice(address(sgdToken)), SGD_USD_PRICE);
        assertEq(priceFeed.getLatestPrice(address(usdToken)), 1e18);
        
        // 验证Vault设置正确
        assertEq(address(sgdVault.asset()), address(sgdToken));
        assertEq(address(usdVault.asset()), address(usdToken));
        assertEq(sgdVault.name(), "SGD Vault");
        assertEq(usdVault.name(), "USD Vault");
        
        // 验证流动性提供者设置
        assertTrue(sgdVault.isLiquidityProvider(marketMaker));
        assertTrue(usdVault.isLiquidityProvider(marketMaker));
        
        // 验证初始存款
        assertEq(sgdVault.balanceOf(marketMaker), DEPOSIT_AMOUNT);
        assertEq(usdVault.balanceOf(marketMaker), DEPOSIT_AMOUNT);
        assertEq(sgdVault.totalAssets(), DEPOSIT_AMOUNT);
        assertEq(usdVault.totalAssets(), DEPOSIT_AMOUNT);
    }
    
    // 测试普通用户存款功能
    function test_Deposit() public {
        // 给用户角色授权
        vm.prank(admin);
        sgdVault.addLiquidityProvider(user1);
        
        // 用户存款
        vm.startPrank(user1);
        sgdToken.approve(address(sgdVault), DEPOSIT_AMOUNT);
        uint256 shares = sgdVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 验证存款结果
        assertEq(sgdVault.balanceOf(user1), shares);
        assertEq(sgdVault.totalAssets(), DEPOSIT_AMOUNT * 2);
        assertTrue(sgdVault.isLiquidityProvider(user1));
    }
    
    // 测试非流动性提供者存款失败
    function test_Deposit_Unauthorized() public {
        vm.startPrank(user2);
        sgdToken.approve(address(sgdVault), DEPOSIT_AMOUNT);
        
        // 非流动性提供者应该无法存款
        vm.expectRevert(abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            user2,
            sgdVault.MARKET_MAKER_ROLE()
        ));
        sgdVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }
    
    // 测试存款金额为零失败
    function test_Deposit_ZeroAmount() public {
        vm.prank(admin);
        sgdVault.addLiquidityProvider(user1);
        
        vm.startPrank(user1);
        sgdToken.approve(address(sgdVault), DEPOSIT_AMOUNT);
        
        // 存款金额为零应该失败
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector));
        sgdVault.deposit(0);
        vm.stopPrank();
    }
    
    // 测试赎回功能
    function test_Redeem() public {
        // 首先存款
        vm.prank(admin);
        sgdVault.addLiquidityProvider(user1);
        
        vm.startPrank(user1);
        sgdToken.approve(address(sgdVault), DEPOSIT_AMOUNT);
        uint256 shares = sgdVault.deposit(DEPOSIT_AMOUNT);
        
        // 然后赎回一半
        uint256 redeemShares = shares / 2;
        uint256 assets = sgdVault.redeem(redeemShares);
        vm.stopPrank();
        
        // 验证赎回结果
        assertEq(sgdVault.balanceOf(user1), shares - redeemShares);
        assertApproxEqRel(assets, DEPOSIT_AMOUNT / 2, 1e15); // 允许一点误差
        assertTrue(sgdVault.isLiquidityProvider(user1)); // 还未全部赎回，仍是流动性提供者
    }
    
    // 测试赎回全部份额
    function test_RedeemAll() public {
        // 首先存款
        vm.prank(admin);
        sgdVault.addLiquidityProvider(user1);
        
        vm.startPrank(user1);
        sgdToken.approve(address(sgdVault), DEPOSIT_AMOUNT);
        uint256 shares = sgdVault.deposit(DEPOSIT_AMOUNT);
        
        // 赎回全部
        sgdVault.redeem(shares);
        vm.stopPrank();
        
        // 验证赎回结果
        assertEq(sgdVault.balanceOf(user1), 0);
        assertFalse(sgdVault.isLiquidityProvider(user1)); // 全部赎回后，不再是流动性提供者
    }
    
    // 测试执行Vault间的交换
    function test_ExecuteSwap() public {
        uint256 swapAmount = 1000 * 1e18; // 1000 SGD
        
        // 为用户设置MARKET_MAKER_ROLE以实现交换功能
        vm.startPrank(admin);
        sgdVault.grantRole(sgdVault.MARKET_MAKER_ROLE(), user1);
        usdVault.grantRole(usdVault.MARKET_MAKER_ROLE(), user1);
        // 确保每个vault都认可对方为有效vault
        vm.stopPrank();
        
        // 记录交换前的余额
        uint256 usdBalanceBefore = usdToken.balanceOf(user1);
        
        // 执行从SGD到USD的交换
        vm.startPrank(user1);
        sgdToken.approve(address(sgdVault), swapAmount);
        
        // 计算预期输出金额
        uint256 expectedUsd = (swapAmount * SGD_USD_PRICE) / 1e18;
        expectedUsd = expectedUsd * 997 / 1000; // 减去0.3%手续费
        
        // 执行交换
        uint256 amountOut = sgdVault.executeSwap(
            address(usdVault),
            swapAmount,
            expectedUsd * 98 / 100 // 设置2%的滑点容忍度
        );
        vm.stopPrank();
        
        // 验证交换结果
        assertApproxEqRel(amountOut, expectedUsd, 1e16); // 允许一点误差
        assertEq(usdToken.balanceOf(user1), usdBalanceBefore + amountOut);
    }
    
    // 测试跨Vault交换滑点保护
    function test_ExecuteSwap_SlippageProtection() public {
        uint256 swapAmount = 1000 * 1e18; // 1000 SGD
        
        vm.startPrank(admin);
        sgdVault.grantRole(sgdVault.MARKET_MAKER_ROLE(), user1);
        usdVault.grantRole(usdVault.MARKET_MAKER_ROLE(), user1);
        vm.stopPrank();
        
        // 执行从SGD到USD的交换，但设置过高的最低输出要求
        vm.startPrank(user1);
        sgdToken.approve(address(sgdVault), swapAmount);
        
        // 计算实际输出金额
        uint256 expectedUsd = (swapAmount * SGD_USD_PRICE) / 1e18;
        expectedUsd = expectedUsd * 997 / 1000; // 减去0.3%手续费
        
        // 设置一个不可能达到的最低输出要求（比预期高20%）
        uint256 impossibleMinOut = expectedUsd * 120 / 100;
        
        // 交换应该因为滑点保护而失败
        vm.expectRevert(abi.encodeWithSelector(Errors.SlippageTooHigh.selector));
        sgdVault.executeSwap(address(usdVault), swapAmount, impossibleMinOut);
        vm.stopPrank();
    }
    
    // 测试费用分配功能
    function test_DistributeFees() public {
        // 首先让两个用户进行多次交换，积累手续费
        uint256 swapAmount = 1000 * 1e18;
        
        vm.startPrank(admin);
        sgdVault.grantRole(sgdVault.MARKET_MAKER_ROLE(), user1);
        sgdVault.grantRole(sgdVault.MARKET_MAKER_ROLE(), user2);
        usdVault.grantRole(usdVault.MARKET_MAKER_ROLE(), user1);
        usdVault.grantRole(usdVault.MARKET_MAKER_ROLE(), user2);
        vm.stopPrank();
        
        // 执行多次交换
        for (uint i = 0; i < 5; i++) {
            // 用户1交换SGD到USD
            vm.startPrank(user1);
            sgdToken.approve(address(sgdVault), swapAmount);
            sgdVault.executeSwap(address(usdVault), swapAmount, 0);
            vm.stopPrank();
            
            // 用户2交换USD到SGD
            vm.startPrank(user2);
            usdToken.approve(address(usdVault), swapAmount);
            usdVault.executeSwap(address(sgdVault), swapAmount, 0);
            vm.stopPrank();
        }
        
        // 记录分配前的余额
        uint256 marketMakerSgdBefore = sgdToken.balanceOf(marketMaker);
        
        // 分配SGD Vault中的手续费
        vm.prank(marketMaker);
        sgdVault.distributeFees();
        
        // 验证手续费已分配给流动性提供者
        uint256 marketMakerSgdAfter = sgdToken.balanceOf(marketMaker);
        assertTrue(marketMakerSgdAfter > marketMakerSgdBefore);
    }
    
    // 测试更新交换费率
    function test_SetSwapFee() public {
        uint256 newFee = 50; // 0.5%
        
        // 更新费率
        vm.prank(admin);
        sgdVault.setSwapFee(newFee);
        
        // 验证费率已更新
        assertEq(sgdVault.swapFee(), newFee);
    }
    
    // 测试更新最大滑点
    function test_SetMaxSlippage() public {
        uint256 newSlippage = 100; // 1%
        
        // 更新最大滑点
        vm.prank(admin);
        sgdVault.setMaxSlippage(newSlippage);
        
        // 验证最大滑点已更新
        assertEq(sgdVault.maxSlippage(), newSlippage);
    }
    
    // 测试添加流动性提供者
    function test_AddLiquidityProvider() public {
        // 添加新的流动性提供者
        vm.prank(admin);
        sgdVault.addLiquidityProvider(user1);
        
        // 验证添加成功
        assertTrue(sgdVault.isLiquidityProvider(user1));
        assertTrue(sgdVault.hasRole(sgdVault.MARKET_MAKER_ROLE(), user1));
    }
    
    // 测试移除流动性提供者
    function test_RemoveLiquidityProvider() public {
        // 先添加
        vm.prank(admin);
        sgdVault.addLiquidityProvider(user1);
        
        // 再移除
        vm.prank(admin);
        sgdVault.removeLiquidityProvider(user1);
        
        // 验证移除成功
        assertFalse(sgdVault.isLiquidityProvider(user1));
        assertFalse(sgdVault.hasRole(sgdVault.MARKET_MAKER_ROLE(), user1));
    }
    
    // 测试暂停Vault功能
    function test_VaultPause() public {
        // 暂停Vault
        vm.prank(admin);
        governance.pauseVault(address(sgdVault));
        
        // 验证Vault已暂停
        assertTrue(governance.isVaultPaused(address(sgdVault)));
        
        // 尝试在暂停状态下存款应该失败
        vm.startPrank(marketMaker);
        sgdToken.approve(address(sgdVault), DEPOSIT_AMOUNT);
        vm.expectRevert(abi.encodeWithSelector(Errors.VaultPaused.selector));
        sgdVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
        
        // 恢复Vault
        vm.prank(admin);
        governance.unpauseVault(address(sgdVault));
        
        // 验证Vault已恢复
        assertFalse(governance.isVaultPaused(address(sgdVault)));
        
        // 现在应该可以存款
        vm.startPrank(marketMaker);
        sgdVault.deposit(DEPOSIT_AMOUNT);
        vm.stopPrank();
    }
    
    // 测试存取款转换函数
    function test_ConversionFunctions() public {
        // 测试convertToShares
        uint256 assets = 1000 * 1e18;
        uint256 shares = sgdVault.convertToShares(assets);
        assertEq(shares, assets); // 初始1:1比例
        
        // 测试convertToAssets
        uint256 convertedAssets = sgdVault.convertToAssets(shares);
        assertEq(convertedAssets, assets);
    }
} 