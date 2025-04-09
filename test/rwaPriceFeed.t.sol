// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/rwaPriceFeed.sol";
import "../src/library/Errors.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract PriceFeedTest is Test {
    // 测试账户
    address public admin = address(1);
    address public priceUpdater = address(2);
    address public unauthorizedUser = address(3);
    
    // 合约实例
    BlockVirtualPriceFeed public priceFeed;
    
    // 模拟代币地址
    address public sgdToken = address(10);
    address public usdToken = address(11);
    address public rwaToken = address(12);
    
    // 常量
    uint256 public constant SGD_USD_PRICE = 0.75 * 1e18; // 1 SGD = 0.75 USD
    uint256 public constant USD_SGD_PRICE = 1.33 * 1e18; // 1 USD = 1.33 SGD
    uint256 public constant RWA_USD_PRICE = 100 * 1e18;  // 1 RWA = 100 USD
    
    function setUp() public {
        vm.startPrank(address(this));
        
        // 部署价格馈送合约
        priceFeed = new BlockVirtualPriceFeed();
        
        // 设置角色
        priceFeed.grantRole(priceFeed.ADMIN_ROLE(), admin);
        priceFeed.grantRole(priceFeed.PRICE_UPDATER_ROLE(), priceUpdater);
        
        // 重要：撤销部署者的权限，以确保权限测试正确
        priceFeed.revokeRole(priceFeed.ADMIN_ROLE(), address(this));
        priceFeed.revokeRole(priceFeed.PRICE_UPDATER_ROLE(), address(this));
        
        vm.stopPrank();
    }
    
    // 测试角色分配是否正确
    function test_RoleAssignment() public {
        bytes32 defaultAdminRole = 0x00;
        assertTrue(priceFeed.hasRole(defaultAdminRole, address(this)));
        assertTrue(priceFeed.hasRole(priceFeed.ADMIN_ROLE(), admin));
        assertTrue(priceFeed.hasRole(priceFeed.PRICE_UPDATER_ROLE(), priceUpdater));
        assertFalse(priceFeed.hasRole(priceFeed.ADMIN_ROLE(), unauthorizedUser));
        assertFalse(priceFeed.hasRole(priceFeed.PRICE_UPDATER_ROLE(), unauthorizedUser));
    }
    
    // 测试管理员注册新代币
    function test_RegisterToken() public {
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // 验证代币已注册
        assertTrue(priceFeed.isTokenRegistered(sgdToken));
        
        // 验证注册代币列表
        address[] memory tokens = priceFeed.getAllTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], sgdToken);
    }
    
    // 测试非管理员尝试注册代币失败
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
    
    // 测试注册零地址失败
    function test_RegisterToken_ZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        priceFeed.registerToken(address(0));
    }
    
    // 测试重复注册代币失败
    function test_RegisterToken_AlreadyRegistered() public {
        // 先注册一次
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // 再次注册应该失败
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.TokenAlreadyRegistered.selector));
        priceFeed.registerToken(sgdToken);
    }
    
    // 测试价格更新员更新价格
    function test_UpdatePrice() public {
        // 先注册代币
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // 更新价格
        vm.prank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
        
        // 验证价格更新成功
        assertEq(priceFeed.getLatestPrice(sgdToken), SGD_USD_PRICE);
        
        // 验证时间戳不为零
        assertTrue(priceFeed.getPriceTimestamp(sgdToken) > 0);
    }
    
    // 测试更新未注册代币价格失败
    function test_UpdatePrice_NotRegistered() public {
        // 未注册代币尝试更新价格
        vm.prank(priceUpdater);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAddress.selector));
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
    }
    
    // 测试非价格更新员尝试更新价格失败
    function test_UpdatePrice_Unauthorized() public {
        // 先注册代币
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        bytes memory revertData = abi.encodeWithSignature(
            "AccessControlUnauthorizedAccount(address,bytes32)",
            unauthorizedUser,
            priceFeed.PRICE_UPDATER_ROLE()
        );
        
        // 未授权用户尝试更新价格
        vm.expectRevert(revertData);
        vm.prank(unauthorizedUser);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
    }
    
    // 测试更新零地址的价格失败
    function test_UpdatePrice_ZeroAddress() public {
        vm.prank(priceUpdater);
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector));
        priceFeed.updatePrice(address(0), SGD_USD_PRICE);
    }
    
    // 测试更新价格为零失败
    function test_UpdatePrice_ZeroPrice() public {
        // 先注册代币
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // 尝试更新价格为零
        vm.prank(priceUpdater);
        vm.expectRevert(abi.encodeWithSelector(Errors.InvalidAmount.selector));
        priceFeed.updatePrice(sgdToken, 0);
    }
    
    // 测试获取未设置价格的代币价格失败
    function test_GetLatestPrice_NotAvailable() public {
        // 注册代币但不设置价格
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // 尝试获取价格应该失败
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceNotAvailable.selector));
        priceFeed.getLatestPrice(sgdToken);
    }
    
    // 测试获取未注册代币的价格失败
    function test_GetLatestPrice_NotRegistered() public {
        // 尝试获取未注册代币的价格
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceNotAvailable.selector));
        priceFeed.getLatestPrice(usdToken);
    }
    
    // 测试计算代币之间的转换
    function test_CalculateConversion() public {
        // 注册两个代币
        vm.startPrank(admin);
        priceFeed.registerToken(sgdToken);
        priceFeed.registerToken(usdToken);
        vm.stopPrank();
        
        // 设置价格
        vm.startPrank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
        priceFeed.updatePrice(usdToken, 1e18); // 1 USD = 1 USD (基准价格)
        vm.stopPrank();
        
        // 计算100 SGD转换为USD
        uint256 sgdAmount = 100 * 1e18;
        uint256 usdAmount = priceFeed.calculateConversion(sgdToken, usdToken, sgdAmount);
        
        // 100 SGD * 0.75 = 75 USD
        assertEq(usdAmount, 75 * 1e18);
        
        // 计算相同代币的转换
        uint256 sameTokenAmount = priceFeed.calculateConversion(sgdToken, sgdToken, sgdAmount);
        assertEq(sameTokenAmount, sgdAmount); // 应该返回相同金额
    }
    
    // 测试复杂的多代币转换
    function test_MultiTokenConversion() public {
        // 注册三个代币
        vm.startPrank(admin);
        priceFeed.registerToken(sgdToken);
        priceFeed.registerToken(usdToken);
        priceFeed.registerToken(rwaToken);
        vm.stopPrank();
        
        // 设置价格
        vm.startPrank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE); // 1 SGD = 0.75 USD
        priceFeed.updatePrice(usdToken, 1e18); // 1 USD = 1 USD (基准价格)
        priceFeed.updatePrice(rwaToken, RWA_USD_PRICE); // 1 RWA = 100 USD
        vm.stopPrank();
        
        // 计算1000 SGD转换为RWA
        uint256 sgdAmount = 1000 * 1e18;
        uint256 rwaAmount = priceFeed.calculateConversion(sgdToken, rwaToken, sgdAmount);
        
        // 1000 SGD * 0.75 / 100 = 7.5 RWA
        assertEq(rwaAmount, 75 * 1e17);
        
        // 反向计算：1 RWA转换为SGD
        uint256 oneRwa = 1e18;
        uint256 sgdFromRwa = priceFeed.calculateConversion(rwaToken, sgdToken, oneRwa);
        
        // 1 RWA * 100 / 0.75 = 133.33... SGD
        assertApproxEqRel(sgdFromRwa, 1333333333333333333e2, 1e15); // 允许小误差
    }
    
    // 测试计算转换时缺少价格信息失败
    function test_CalculateConversion_PriceNotAvailable() public {
        // 注册代币但不设置价格
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // 也注册并设置另一个代币的价格
        vm.prank(admin);
        priceFeed.registerToken(usdToken);
        
        vm.prank(priceUpdater);
        priceFeed.updatePrice(usdToken, 1e18);
        
        // 尝试计算转换应该失败
        vm.expectRevert(abi.encodeWithSelector(Errors.PriceNotAvailable.selector));
        priceFeed.calculateConversion(sgdToken, usdToken, 100 * 1e18);
    }
    
    // 测试查询所有注册代币
    function test_GetAllTokens() public {
        // 初始状态应该没有注册代币
        address[] memory initialTokens = priceFeed.getAllTokens();
        assertEq(initialTokens.length, 0);
        
        // 注册多个代币
        vm.startPrank(admin);
        priceFeed.registerToken(sgdToken);
        priceFeed.registerToken(usdToken);
        priceFeed.registerToken(rwaToken);
        vm.stopPrank();
        
        // 验证注册代币列表
        address[] memory tokens = priceFeed.getAllTokens();
        assertEq(tokens.length, 3);
        assertEq(tokens[0], sgdToken);
        assertEq(tokens[1], usdToken);
        assertEq(tokens[2], rwaToken);
    }
    
    // 测试检查代币是否已注册
    function test_IsTokenRegistered() public {
        // 初始状态代币未注册
        assertFalse(priceFeed.isTokenRegistered(sgdToken));
        
        // 注册代币
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        // 验证代币已注册
        assertTrue(priceFeed.isTokenRegistered(sgdToken));
        assertFalse(priceFeed.isTokenRegistered(usdToken)); // 其他代币仍未注册
    }
    
    // 测试价格更新的时间戳
    function test_PriceTimestamp() public {
        // 注册并设置代币价格
        vm.prank(admin);
        priceFeed.registerToken(sgdToken);
        
        uint256 beforeUpdate = block.timestamp;
        
        // 更新价格
        vm.prank(priceUpdater);
        priceFeed.updatePrice(sgdToken, SGD_USD_PRICE);
        
        // 获取时间戳
        uint256 priceTimestamp = priceFeed.getPriceTimestamp(sgdToken);
        
        // 验证时间戳与当前区块时间相符
        assertEq(priceTimestamp, beforeUpdate);
        
        // 未注册代币的时间戳应为0
        assertEq(priceFeed.getPriceTimestamp(usdToken), 0);
    }
} 