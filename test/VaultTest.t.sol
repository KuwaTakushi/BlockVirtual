// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/virtualGovernance.sol";
import "../src/virtualVault.sol";
import "../src/rwaPriceFeed.sol";
import "../src/rwaToken.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract VaultTest is Test {
    address public admin = address(1);
    address public marketMaker = address(2);
    address public user = address(3);
    
    ERC1967Proxy public governanceProxy;
    ERC1967Proxy public sgdVaultProxy;
    ERC1967Proxy public rwaVaultProxy;
    ERC1967Proxy public sgdTokenProxy;
    ERC1967Proxy public rwaTokenProxy;
    
    BlockVirtualGovernance public governanceImpl;
    VirtualVault public sgdVaultImpl;
    VirtualVault public rwaVaultImpl;
    RwaToken public sgdTokenImpl;
    RwaToken public rwaTokenImpl;
    
    BlockVirtualPriceFeed public priceFeed;
    
    uint256 public constant SINGAPORE_COUNTRY_CODE = 65;
    uint256 public constant KYC_EXPIRY = 365 days;
    
    function setUp() public {
        governanceImpl = new BlockVirtualGovernance();
        sgdVaultImpl = new VirtualVault();
        rwaVaultImpl = new VirtualVault();
        priceFeed = new BlockVirtualPriceFeed();
        sgdTokenImpl = new RwaToken();
        rwaTokenImpl = new RwaToken();
    }
    
    function test_DeployGovernance() public {
        governanceProxy = new ERC1967Proxy(
            address(governanceImpl),
            abi.encodeWithSelector(BlockVirtualGovernance.initialize.selector)
        );
        
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
        vm.stopPrank();
        
        assertTrue(BlockVirtualGovernance(address(governanceProxy)).hasRole(
            keccak256("DEFAULT_ADMIN_ROLE"),
            admin
        ));
        assertTrue(BlockVirtualGovernance(address(governanceProxy)).hasRole(
            keccak256("ADMIN_ROLE"),
            admin
        ));
    }
    
    function test_DeployTokens() public {
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
        
        rwaTokenProxy = new ERC1967Proxy(
            address(rwaTokenImpl),
            abi.encodeWithSelector(
                RwaToken.initialize.selector,
                "Real Estate Token",
                "RWA",
                address(governanceProxy),
                SINGAPORE_COUNTRY_CODE
            )
        );
        
        assertTrue(RwaToken(address(sgdTokenProxy)).blockVirtualGovernance() == address(governanceProxy));
        assertTrue(RwaToken(address(rwaTokenProxy)).blockVirtualGovernance() == address(governanceProxy));
    }
    
    /*function test_DeployVaults() public {
        // 部署金库代理合约
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
        
        rwaVaultProxy = new ERC1967Proxy(
            address(rwaVaultImpl),
            abi.encodeWithSelector(
                VirtualVault.initialize.selector,
                address(governanceProxy),
                address(priceFeed),
                address(rwaTokenProxy),
                "RWA Vault",
                "vRWA"
            )
        );
        
        // 检查金库合约
        //assertTrue(VirtualVault(address(sgdVaultProxy)).asset() == address(sgdTokenProxy));
        //assertTrue(VirtualVault(address(rwaVaultProxy)).asset() == address(rwaTokenProxy));
    }
    
    function test_SetupRoles() public {
        vm.startPrank(admin);
        
        // 设置市场做市商角色
        BlockVirtualGovernance(address(governanceProxy)).grantRole(
            keccak256("MARKET_MAKER_ROLE"),
            marketMaker
        );
        
        // 添加支持的国家代码
        BlockVirtualGovernance(address(governanceProxy)).addSupportedCountryCode(SINGAPORE_COUNTRY_CODE);
        
        // 注册KYC用户
        BlockVirtualGovernance(address(governanceProxy)).registerKYCUser(
            user,
            block.timestamp + KYC_EXPIRY,
            SINGAPORE_COUNTRY_CODE
        );
        
        vm.stopPrank();
        
        // 检查角色设置
        assertTrue(BlockVirtualGovernance(address(governanceProxy)).hasRole(
            keccak256("MARKET_MAKER_ROLE"),
            marketMaker
        ));
        
        // 检查KYC状态
        assertTrue(BlockVirtualGovernance(address(governanceProxy)).getKycStatus(user));
        assertTrue(BlockVirtualGovernance(address(governanceProxy)).isFromSupportedCountry(user));
    }
    
    function test_MintTokens() public {
        vm.startPrank(admin);
        
        // 铸造代币给用户
        RwaToken(address(sgdTokenProxy)).mintRwa(user, 1000 * 10 ** 18);
        RwaToken(address(rwaTokenProxy)).mintRwa(user, 1000 * 10 ** 18);
        
        vm.stopPrank();
        
        // 检查代币余额
        assertTrue(RwaToken(address(sgdTokenProxy)).balanceOf(user) == 1000 * 10 ** 18);
        assertTrue(RwaToken(address(rwaTokenProxy)).balanceOf(user) == 1000 * 10 ** 18);
    }*/
} 