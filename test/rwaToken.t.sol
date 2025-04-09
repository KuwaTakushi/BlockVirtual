// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/virtualGovernance.sol";
import "../src/rwaToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RwaTokenTest is Test {
    // 测试账户
    address public admin = address(1);
    address public operator = address(2);
    address public user1 = address(3);
    address public user2 = address(4);
    address public user3 = address(5);
    address public nonKycUser = address(6);
    address public foreignUser = address(7);
    address public blacklistedUser = address(8);
    
    // 代理合约和实现合约
    ERC1967Proxy public governanceProxy;
    ERC1967Proxy public sgdTokenProxy;
    
    BlockVirtualGovernance public governanceImpl;
    RwaToken public sgdTokenImpl;
    
    // 常量
    uint256 public constant SINGAPORE_COUNTRY_CODE = 702;
    uint256 public constant FOREIGN_COUNTRY_CODE = 840; // 美国
    uint256 public constant KYC_EXPIRY = 365 days;
    
    function setUp() public {
        // 部署实现合约
        governanceImpl = new BlockVirtualGovernance();
        sgdTokenImpl = new RwaToken();
        
        // 部署和初始化治理代理
        governanceProxy = new ERC1967Proxy(
            address(governanceImpl),
            abi.encodeWithSelector(BlockVirtualGovernance.initialize.selector)
        );
        
        // 设置治理合约权限
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
        
        // 部署SGD代币代理
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
        
        // 添加支持的国家代码
        vm.prank(admin);
        BlockVirtualGovernance(address(governanceProxy)).addSupportedCountryCode(SINGAPORE_COUNTRY_CODE);
        
        // 为测试用户设置KYC
        vm.startPrank(operator);
        
        // 为新加坡用户注册KYC
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
        
        // 为外国用户注册KYC
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            foreignUser, 
            block.timestamp + KYC_EXPIRY, 
            FOREIGN_COUNTRY_CODE
        );
        
        // 将一个用户加入黑名单
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            blacklistedUser
        );
        
        vm.stopPrank();
    }
    
    // 测试代币初始化是否正确
    function test_TokenInitialization() public {
        // 验证代币初始化正确
        assertEq(RwaToken(address(sgdTokenProxy)).name(), "Singapore Dollar");
        assertEq(RwaToken(address(sgdTokenProxy)).symbol(), "SGD");
        assertEq(RwaToken(address(sgdTokenProxy)).blockVirtualGovernance(), address(governanceProxy));
        assertEq(RwaToken(address(sgdTokenProxy)).supportedCountryCode(), SINGAPORE_COUNTRY_CODE);
    }
    
    // 测试铸造RWA代币功能
    function test_MintRwa() public {
        // 只有治理合约可以铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 验证余额
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 1000 ether);
    }
    
    // 测试未授权账户尝试铸造代币
    function test_MintRwa_Unauthorized() public {
        // 非治理合约不能铸造代币
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedRole.selector, admin));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
    }
    
    // 测试对黑名单用户铸造代币失败
    function test_MintRwa_BlacklistedUser() public {
        // 对黑名单用户铸造应该失败
        vm.prank(address(governanceProxy));
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, blacklistedUser));
        RwaToken(address(sgdTokenProxy)).mintRwa(blacklistedUser, 1000 ether);
    }
    
    // 测试燃烧RWA代币功能
    function test_BurnRwa() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 然后燃烧部分代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).burnRwa(user1, 500 ether);
        
        // 验证余额
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 500 ether);
    }
    
    // 测试未授权账户尝试燃烧代币
    function test_BurnRwa_Unauthorized() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 非治理合约不能燃烧代币
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedRole.selector, admin));
        RwaToken(address(sgdTokenProxy)).burnRwa(user1, 500 ether);
    }
    
    // 测试对黑名单用户燃烧代币失败
    function test_BurnRwa_BlacklistedUser() public {
        // 这个测试模拟用户铸造后被加入黑名单，然后尝试燃烧代币
        
        // 设置一个临时用户
        address tempUser = address(100);
        
        // 为临时用户注册KYC
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            tempUser, 
            block.timestamp + KYC_EXPIRY, 
            SINGAPORE_COUNTRY_CODE
        );
        
        // 给临时用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(tempUser, 1000 ether);
        
        // 将用户加入黑名单
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            tempUser
        );
        
        // 尝试燃烧黑名单用户的代币应该失败
        vm.prank(address(governanceProxy));
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, tempUser));
        RwaToken(address(sgdTokenProxy)).burnRwa(tempUser, 500 ether);
    }
    
    // 测试转账功能
    function test_Transfer_Successful() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 转账应该成功
        vm.prank(user1);
        bool success = RwaToken(address(sgdTokenProxy)).transfer(user2, 400 ether);
        
        // 验证结果
        assertTrue(success);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 600 ether);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user2), 400 ether);
    }
    
    // 测试转账给没有KYC的用户失败
    function test_Transfer_NoKyc() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 尝试转账给没有KYC的用户应该失败
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedKycStatus.selector));
        RwaToken(address(sgdTokenProxy)).transfer(nonKycUser, 400 ether);
    }
    
    // 测试转账给不支持国家的用户失败
    function test_Transfer_UnsupportedCountry() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 尝试转账给不支持国家的用户应该失败
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedCountryUser.selector));
        RwaToken(address(sgdTokenProxy)).transfer(foreignUser, 400 ether);
    }
    
    // 测试转账涉及黑名单用户失败
    function test_Transfer_Blacklisted() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 转账给黑名单用户应该失败
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, blacklistedUser));
        RwaToken(address(sgdTokenProxy)).transfer(blacklistedUser, 400 ether);
        
        // 将发送者加入黑名单
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // 黑名单用户尝试转账也应该失败
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, user1));
        RwaToken(address(sgdTokenProxy)).transfer(user2, 400 ether);
    }
    
    // 测试使用transferFrom功能成功
    function test_TransferFrom_Successful() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 批准用户2使用部分代币
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // 用户2执行transferFrom
        vm.prank(user2);
        bool success = RwaToken(address(sgdTokenProxy)).transferFrom(user1, user3, 300 ether);
        
        // 验证结果
        assertTrue(success);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user1), 700 ether);
        assertEq(RwaToken(address(sgdTokenProxy)).balanceOf(user3), 300 ether);
        assertEq(RwaToken(address(sgdTokenProxy)).allowance(user1, user2), 200 ether);
    }
    
    // 测试通过transferFrom转账给没有KYC的用户失败
    function test_TransferFrom_NoKyc() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 批准用户2使用部分代币
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // 尝试转账给没有KYC的用户应该失败
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedKycStatus.selector));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, nonKycUser, 300 ether);
    }
    
    // 测试通过transferFrom转账给不支持国家的用户失败
    function test_TransferFrom_UnsupportedCountry() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 批准用户2使用部分代币
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // 尝试转账给不支持国家的用户应该失败
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UnauthorizedCountryUser.selector));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, foreignUser, 300 ether);
    }
    
    // 测试transferFrom涉及黑名单用户失败
    function test_TransferFrom_Blacklisted() public {
        // 先给用户铸造代币
        vm.prank(address(governanceProxy));
        RwaToken(address(sgdTokenProxy)).mintRwa(user1, 1000 ether);
        
        // 批准用户2使用部分代币
        vm.prank(user1);
        RwaToken(address(sgdTokenProxy)).approve(user2, 500 ether);
        
        // 转账给黑名单用户应该失败
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, blacklistedUser));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, blacklistedUser, 300 ether);
        
        // 将发送者加入黑名单
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // 使用黑名单用户作为源地址也应该失败
        vm.prank(user2);
        vm.expectRevert(abi.encodeWithSelector(Errors.UserBlacklisted.selector, user1));
        RwaToken(address(sgdTokenProxy)).transferFrom(user1, user3, 300 ether);
    }
    
    // 测试合规性检查功能
    function test_CheckCompliance() public {
        // 测试合规性检查
        bool compliant = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, user2);
        assertTrue(compliant);
        
        // 不合规的情况
        bool notCompliant1 = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, nonKycUser);
        assertFalse(notCompliant1);
        
        bool notCompliant2 = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, foreignUser);
        assertFalse(notCompliant2);
        
        bool notCompliant3 = RwaToken(address(sgdTokenProxy)).checkCompliance(user1, blacklistedUser);
        assertFalse(notCompliant3);
    }
    
    // 测试黑名单检查功能
    function test_IsBlacklisted() public {
        // 检查黑名单状态
        assertTrue(RwaToken(address(sgdTokenProxy)).isBlacklisted(blacklistedUser));
        assertFalse(RwaToken(address(sgdTokenProxy)).isBlacklisted(user1));
        
        // 添加用户到黑名单
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).addBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // 验证用户现在在黑名单中
        assertTrue(RwaToken(address(sgdTokenProxy)).isBlacklisted(user1));
        
        // 将用户从黑名单中移除
        vm.prank(operator);
        BlockVirtualGovernance(address(governanceProxy)).removeBlacklisted(
            address(sgdTokenProxy),
            user1
        );
        
        // 验证用户现在不在黑名单中
        assertFalse(RwaToken(address(sgdTokenProxy)).isBlacklisted(user1));
    }
} 