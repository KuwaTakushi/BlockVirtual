// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "src/library/Errors.sol";
import "src/interfaces/IBlockVirtualGovernance.sol";
import "src/virtualVault.sol";

interface IBlockVirtualVault {
    function executeSwap(address toVault, uint256 amountIn, uint256 minAmountOut) external returns (uint256);
    function asset() external view returns (IERC20);
    function _getExpectedAmountOut(address toVault, uint256 amountIn) external view returns (uint256);
}

/**
 * @title VirtualPay
 * @dev Payment platform that uses multiple vaults for cross-border payment and stablecoin settlement
 */
contract VirtualPay is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;
    
    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // State variables
    IBlockVirtualGovernance public governance;
    
    // Mapping token address => vault address
    mapping(address => address) public tokenVaults;
    
    // Fee structure
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public platformFee = 50; // 0.5% default platform fee
    uint256 public totalFees;
    mapping(address => uint256) public feesByToken; // Fees collected by token type
    
    // Payment tracking
    struct Payment {
        address sender;
        address recipient;
        address sourceToken;
        address targetToken;
        uint256 amountIn;
        uint256 amountOut;
        uint256 platformFeeAmount;
        uint256 timestamp;
        bool success;
    }
    
    mapping(bytes32 => Payment) public payments;
    bytes32[] public paymentIds;
    
    // Events
    event PaymentExecuted(
        bytes32 indexed paymentId,
        address indexed sender,
        address indexed recipient,
        address sourceToken,
        address targetToken,
        uint256 amountIn,
        uint256 amountOut,
        uint256 platformFeeAmount
    );
    event FeesWithdrawn(address token, address recipient, uint256 amount);
    event PlatformFeeUpdated(uint256 newFee);
    event VaultSet(address token, address vault);
    
    /**
     * @dev Constructor 
     * @param _governance Governance contract address
     */
    constructor(address _governance) {
        if (_governance == address(0)) revert Errors.ZeroAddress();
        
        governance = IBlockVirtualGovernance(_governance);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }
    
    /**
     * @dev Set vault for a token
     * @param token Token address
     * @param vault Vault address
     */
    function setVault(address token, address vault) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (vault == address(0)) revert Errors.ZeroAddress();
        
        // Verify that the vault is for the correct token
        address vaultToken = address(IBlockVirtualVault(vault).asset());
        if (vaultToken != token) revert Errors.InvalidVault();
        
        tokenVaults[token] = vault;
        emit VaultSet(token, vault);
    }
    
    /**
     * @dev Remove vault for a token
     * @param token Token address
     */
    function removeVault(address token) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert Errors.ZeroAddress();
        address vault = tokenVaults[token];
        if (vault == address(0)) revert Errors.VaultNotFound();
        
        tokenVaults[token] = address(0);
        emit VaultSet(token, address(0));
    }
    
    /**
     * @dev Check if user is compliant with KYC and country restrictions
     * @param user User address to check
     * @param token The token being used (for blacklist check)
     */
    function _checkCompliance(address user, address token) internal view {
        if (user == address(0)) revert Errors.ZeroAddress();
        if (!governance.getKycStatus(user)) revert Errors.UnauthorizedKycStatus();
        if (!governance.isFromSupportedCountry(user)) revert Errors.UnauthorizedCountryUser();
        if (governance.isBlacklisted(token, user)) revert Errors.UserBlacklisted(user);
    }
    
    /**
     * @dev Generate a unique payment ID
     */
    function _generatePaymentId(
        address sender,
        address recipient,
        address sourceToken,
        address targetToken,
        uint256 amount
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                sender,
                recipient,
                sourceToken,
                targetToken,
                amount,
                block.timestamp,
                paymentIds.length
            )
        );
    }
    
    /**
     * @dev Execute a payment from one token to another
     * @param recipient Payment recipient
     * @param sourceToken Source token address
     * @param targetToken Target token address
     * @param amount Amount of source token to send
     * @param minAmountOut Minimum amount of target token to receive (slippage protection)
     * @return paymentId Unique payment identifier
     * @return amountOut Amount of target token received
     */
    function executePayment(
        address recipient,
        address sourceToken,
        address targetToken,
        uint256 amount,
        uint256 minAmountOut
    ) external nonReentrant returns (bytes32 paymentId, uint256 amountOut) {
        // Verify parameters
        if (amount == 0) revert Errors.InvalidAmount();
        if (recipient == address(0)) revert Errors.ZeroAddress();
        if (sourceToken == address(0) || targetToken == address(0)) revert Errors.ZeroAddress();
        if (sourceToken == targetToken) revert Errors.InvalidTokenPair();
        
        // Check compliance
        _checkCompliance(msg.sender, sourceToken);
        _checkCompliance(recipient, targetToken);
        
        // Get vaults for tokens
        address sourceVault = tokenVaults[sourceToken];
        address targetVault = tokenVaults[targetToken];
        
        if (sourceVault == address(0) || targetVault == address(0)) revert Errors.VaultNotFound();
        
        // Generate payment ID
        paymentId = _generatePaymentId(msg.sender, recipient, sourceToken, targetToken, amount);
        
        // Calculate platform fee
        uint256 platformFeeAmount = (amount * platformFee) / FEE_DENOMINATOR;
        uint256 amountAfterFee = amount - platformFeeAmount;
        
        // Transfer tokens from sender to this contract
        IERC20(sourceToken).safeTransferFrom(msg.sender, address(this), amount);
        
        // Add platform fee to total
        feesByToken[sourceToken] += platformFeeAmount;
        totalFees += platformFeeAmount;
        
        // Approve source vault to spend tokens
        IERC20(sourceToken).approve(sourceVault, 0); // Clear previous allowance
        IERC20(sourceToken).approve(sourceVault, amountAfterFee);
        
        // Execute swap through vault
        try IBlockVirtualVault(sourceVault).executeSwap(targetVault, amountAfterFee, minAmountOut) returns (uint256 swapAmount) {
            amountOut = swapAmount;
            
            // Record payment
            payments[paymentId] = Payment({
                sender: msg.sender,
                recipient: recipient,
                sourceToken: sourceToken,
                targetToken: targetToken,
                amountIn: amount,
                amountOut: amountOut,
                platformFeeAmount: platformFeeAmount,
                timestamp: block.timestamp,
                success: true
            });
            
            paymentIds.push(paymentId);
            
            emit PaymentExecuted(
                paymentId,
                msg.sender,
                recipient,
                sourceToken,
                targetToken,
                amount,
                amountOut,
                platformFeeAmount
            );
            
            return (paymentId, amountOut);
        } catch {
            // Refund tokens if swap fails
            IERC20(sourceToken).safeTransfer(msg.sender, amount);
            
            // Record failed payment
            payments[paymentId] = Payment({
                sender: msg.sender,
                recipient: recipient,
                sourceToken: sourceToken,
                targetToken: targetToken,
                amountIn: amount,
                amountOut: 0,
                platformFeeAmount: 0,
                timestamp: block.timestamp,
                success: false
            });
            
            revert Errors.SwapFailed();
        }
    }
    
    /**
     * @dev Estimate amount out for a payment
     * @param sourceToken Source token address
     * @param targetToken Target token address
     * @param amount Amount of source token to send
     * @return estimatedAmount Estimated amount of target token to receive
     * @return fee Platform fee amount
     */
    function estimatePayment(
        address sourceToken, 
        address targetToken, 
        uint256 amount
    ) external view returns (uint256 estimatedAmount, uint256 fee) {
        if (amount == 0) return (0, 0);
        if (sourceToken == targetToken) return (amount, 0);
        
        // Get vaults for tokens
        address sourceVault = tokenVaults[sourceToken];
        address targetVault = tokenVaults[targetToken];
        
        if (sourceVault == address(0) || targetVault == address(0)) return (0, 0);
        
        // Calculate platform fee
        fee = (amount * platformFee) / FEE_DENOMINATOR;
        uint256 amountAfterFee = amount - fee;
        
        // Get price data from source vault
        try IBlockVirtualVault(sourceVault)._getExpectedAmountOut(targetVault, amountAfterFee) returns (uint256 expectedAmount) {
            return (expectedAmount, fee);
        } catch {
            return (0, fee);
        }
    }
    
    /**
     * @dev Withdraw collected fees for a specific token
     * @param token Token address
     * @param recipient Fee recipient
     */
    function withdrawFees(address token, address recipient) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert Errors.ZeroAddress();
        if (recipient == address(0)) revert Errors.ZeroAddress();
        
        uint256 feeAmount = feesByToken[token];
        if (feeAmount == 0) revert Errors.InsufficientBalance();
        
        // Reset fee amount
        feesByToken[token] = 0;
        
        // Transfer fees to recipient
        IERC20(token).safeTransfer(recipient, feeAmount);
        
        emit FeesWithdrawn(token, recipient, feeAmount);
    }
    
    /**
     * @dev Set platform fee
     * @param _fee New fee in basis points (1 = 0.01%)
     */
    function setPlatformFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
        if (_fee > 500) revert Errors.ExceedsLimit(_fee, 500); // Max 5%
        platformFee = _fee;
        emit PlatformFeeUpdated(_fee);
    }
    
    /**
     * @dev Get payment by ID
     * @param paymentId Payment ID
     * @return Payment details
     */
    function getPayment(bytes32 paymentId) external view returns (Payment memory) {
        return payments[paymentId];
    }
    
    /**
     * @dev Get all payment IDs
     * @return Array of payment IDs
     */
    function getAllPaymentIds() external view returns (bytes32[] memory) {
        return paymentIds;
    }
    
    /**
     * @dev Get number of payments
     * @return Number of payments
     */
    function getPaymentCount() external view returns (uint256) {
        return paymentIds.length;
    }
    
    /**
     * @dev Get fees collected for all tokens
     * @param tokens Array of token addresses
     * @return Array of fee amounts
     */
    function getFeesByTokens(address[] memory tokens) external view returns (uint256[] memory) {
        uint256[] memory fees = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            fees[i] = feesByToken[tokens[i]];
        }
        return fees;
    }
}
