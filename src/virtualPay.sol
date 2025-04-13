// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./pool/virtualPool.sol";
import "./interfaces/IBlockVirtualGovernance.sol";
import "./library/Errors.sol";


contract VirtualPay is 
    Initializable, 
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable 
{
    using SafeERC20 for IERC20;

    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    // State variables
    VirtualPool public pool;
    IBlockVirtualGovernance public governance;
    
    // Events
    event PaymentProcessed(
        address indexed from,
        address indexed to,
        address indexed tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );
    
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _pool, address _governance) public initializer {
        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        if (_pool == address(0) || _governance == address(0)) revert Errors.ZeroAddress();
        
        pool = VirtualPool(_pool);
        governance = IBlockVirtualGovernance(_governance);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }
    
    function _authorizeUpgrade(address) internal override onlyRole(ADMIN_ROLE) {}
    
    /**
     * @dev Processes a payment by swapping tokens through the pool
     * @param recipient Payment recipient
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amountIn Input amount
     * @param minAmountOut Minimum output amount
     * @return amountOut Amount of output tokens received
     */
    function processPayment(
        address recipient,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external whenNotPaused returns (uint256 amountOut) {
        // Check KYC status
        if (!governance.getKycStatus(msg.sender)) revert Errors.KYCNotVerified(msg.sender);
        if (!governance.getKycStatus(recipient)) revert Errors.KYCNotVerified(recipient);
        
        // Approve tokens to pool
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenIn).approve(address(pool), amountIn);
        
        // Execute swap through pool
        amountOut = pool.swap(tokenIn, tokenOut, amountIn, minAmountOut);
        
        // Transfer output tokens to recipient
        IERC20(tokenOut).safeTransfer(recipient, amountOut);
        
        emit PaymentProcessed(msg.sender, recipient, tokenIn, tokenOut, amountIn, amountOut);
        return amountOut;
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }
    
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    uint256[50] private __gap;
} 