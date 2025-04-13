// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "src/interfaces/IBlockVirtualGovernance.sol";
import "src/rwaPriceFeed.sol";
import "src/library/Errors.sol";
import "src/library/PoolManager.sol";

contract VirtualPool is 
    Initializable, 
    AccessControlUpgradeable, 
    ReentrancyGuardUpgradeable, 
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using PoolManager for mapping(address => PoolManager.PoolRegistry);

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    IBlockVirtualGovernance public governance;
    BlockVirtualPriceFeed public priceFeed;
    address public feeCollector;
    
    // Fee parameters (expressed in basis points, 1 bp = 0.01%)
    uint256 public swapFee = 30; // 0.3% default swap fee
    uint256 public liquidityFee = 5; // 0.05% default liquidity fee
    uint256 public constant MAX_FEE = 1000; // 10% maximum fee
    
    // Token pair storage
    struct Pair {
        address token0;
        address token1;
        address pairToken; // ERC20 token representing liquidity
        uint256 reserve0;
        uint256 reserve1;
        uint256 totalSupply;
        bool exists;
    }
    

    // token0 => token1 => pair address
    mapping(address => mapping(address => address)) public getPair;
    mapping(bytes32 => Pair) public pairs;
    mapping(address => bool) public supportedTokens;

    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pairToken, uint256 indexed pairId);
    event Swap(address indexed user, address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut);
    event LiquidityAdded(address indexed user, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event LiquidityRemoved(address indexed user, address indexed token0, address indexed token1, uint256 amount0, uint256 amount1, uint256 liquidity);
    event FeeCollectorSet(address indexed oldCollector, address indexed newCollector);
    event SwapFeeUpdated(uint256 oldFee, uint256 newFee);
    event LiquidityFeeUpdated(uint256 oldFee, uint256 newFee);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    
    modifier validToken(address token) {
        if (!supportedTokens[token]) revert Errors.UnsupportedToken();
        _;
    }
    
    modifier tokenPairExists(address token0, address token1) {
        if (getPair[token0][token1] == address(0)) revert Errors.InvalidTokenPair();
        _;
    }
    
    modifier kycVerified(address user) {
        if (!governance.getKycStatus(user)) revert Errors.KYCNotVerified(user);
        _;
    }
    
    modifier notBlacklisted(address user, address token) {
        if (governance.isBlacklisted(token, user)) revert Errors.Blacklisted(user);
        _;
    }
    
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _governance) public initializer {
        if (_governance == address(0)) revert Errors.ZeroAddress();
        
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        
        governance = IBlockVirtualGovernance(_governance);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(FEE_MANAGER_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
    }
    
    function _authorizeUpgrade(address) internal override onlyRole(ADMIN_ROLE) {}
    
    function setPriceFeed(address _priceFeed) external onlyRole(ADMIN_ROLE) {
        if (_priceFeed == address(0)) revert Errors.ZeroAddress();
        priceFeed = BlockVirtualPriceFeed(_priceFeed);
    }
    
    function setFeeCollector(address _feeCollector) external onlyRole(FEE_MANAGER_ROLE) {
        if (_feeCollector == address(0)) revert Errors.ZeroAddress();
        address oldCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorSet(oldCollector, _feeCollector);
    }
    
    function setSwapFee(uint256 _swapFee) external onlyRole(FEE_MANAGER_ROLE) {
        if (_swapFee > MAX_FEE) revert Errors.InvalidInput();
        uint256 oldFee = swapFee;
        swapFee = _swapFee;
        emit SwapFeeUpdated(oldFee, _swapFee);
    }
    
    function setLiquidityFee(uint256 _liquidityFee) external onlyRole(FEE_MANAGER_ROLE) {
        if (_liquidityFee > MAX_FEE) revert Errors.InvalidInput();
        uint256 oldFee = liquidityFee;
        liquidityFee = _liquidityFee;
        emit LiquidityFeeUpdated(oldFee, _liquidityFee);
    }
    
    function addSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        if (token == address(0)) revert Errors.ZeroAddress();
        supportedTokens[token] = true;
        emit TokenAdded(token);
    }
    
    function removeSupportedToken(address token) external onlyRole(ADMIN_ROLE) {
        supportedTokens[token] = false;
        emit TokenRemoved(token);
    }
    
    /**
     * @dev Creates a new token pair for liquidity and swaps
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return pairToken Address of the liquidity token
     */
    function createPair(address tokenA, address tokenB) 
        external 
        onlyRole(ADMIN_ROLE)
        validToken(tokenA)
        validToken(tokenB)
        returns (address pairToken) 
    {
        if (tokenA == tokenB) revert Errors.InvalidTokenPair();
        if (getPair[tokenA][tokenB] != address(0) || getPair[tokenB][tokenA] != address(0)) {
            revert Errors.TokenAlreadyRegistered();
        }
        
        // Sort tokens to ensure consistent ordering
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        // Generate a unique pair ID
        bytes32 pairId = keccak256(abi.encodePacked(token0, token1));
        
        // Create a unique address for the pair (could be implemented as a real ERC20 token)
        pairToken = address(uint160(uint256(pairId)));
        
        // Store the pair
        getPair[token0][token1] = pairToken;
        getPair[token1][token0] = pairToken;
        
        pairs[pairId] = Pair({
            token0: token0,
            token1: token1,
            pairToken: pairToken,
            reserve0: 0,
            reserve1: 0,
            totalSupply: 0,
            exists: true
        });
        
        allPairs.push(pairToken);
        
        emit PairCreated(token0, token1, pairToken, allPairs.length - 1);
        
        return pairToken;
    }
    
    /**
     * @dev Swaps tokens
     * @param tokenIn Address of input token
     * @param tokenOut Address of output token
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum acceptable amount of output tokens
     * @return amountOut Amount of output tokens received
     */
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) 
        external
        whenNotPaused
        nonReentrant
        validToken(tokenIn)
        validToken(tokenOut)
        kycVerified(msg.sender)
        notBlacklisted(msg.sender, tokenIn)
        notBlacklisted(msg.sender, tokenOut)
        tokenPairExists(tokenIn, tokenOut)
        returns (uint256 amountOut)
    {
        if (tokenIn == tokenOut) revert Errors.InvalidTokenPair();
        if (amountIn == 0) revert Errors.InvalidAmount();
        
        // Sort tokens to get the correct pair ordering
        (address token0, address token1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        
        // Get pair ID and data
        bytes32 pairId = keccak256(abi.encodePacked(token0, token1));
        Pair storage pair = pairs[pairId];
        
        if (!pair.exists) revert Errors.InvalidTokenPair();
        
        // Determine which token is being swapped in
        bool isToken0In = tokenIn == token0;
        
        // Get reserves
        uint256 reserveIn = isToken0In ? pair.reserve0 : pair.reserve1;
        uint256 reserveOut = isToken0In ? pair.reserve1 : pair.reserve0;
        
        if (reserveIn == 0 || reserveOut == 0) revert Errors.InsufficientAmount();
        
        // Calculate fee amount
        uint256 feeAmount = (amountIn * swapFee) / 10000;
        uint256 amountInWithFee = amountIn - feeAmount;
        
        // Calculate amount out using constant product formula k = x * y
        // (x + dx) * (y - dy) = x * y
        // dy = y * dx / (x + dx)
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
        
        if (amountOut < amountOutMin) revert Errors.SlippageTooHigh();
        
        // Transfer tokens from sender to this contract
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Transfer fee to fee collector if set
        if (feeCollector != address(0) && feeAmount > 0) {
            IERC20(tokenIn).safeTransfer(feeCollector, feeAmount);
        }
        
        // Transfer output tokens to sender
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
        
        // Update reserves
        if (isToken0In) {
            pair.reserve0 += amountInWithFee;
            pair.reserve1 -= amountOut;
        } else {
            pair.reserve0 -= amountOut;
            pair.reserve1 += amountInWithFee;
        }
        
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);
        
        return amountOut;
    }
    
    /**
     * @dev Adds liquidity to a pool
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param amountADesired Desired amount of first token
     * @param amountBDesired Desired amount of second token
     * @param amountAMin Minimum acceptable amount of first token
     * @param amountBMin Minimum acceptable amount of second token
     * @return amountA Amount of first token used
     * @return amountB Amount of second token used
     * @return liquidity Liquidity tokens minted
     */
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) 
        external
        whenNotPaused
        nonReentrant
        validToken(tokenA)
        validToken(tokenB)
        kycVerified(msg.sender)
        notBlacklisted(msg.sender, tokenA)
        notBlacklisted(msg.sender, tokenB)
        returns (uint256 amountA, uint256 amountB, uint256 liquidity)
    {

        if (tokenA == tokenB) revert Errors.InvalidTokenPair();
        if (amountADesired == 0 || amountBDesired == 0) revert Errors.InvalidAmount();
        
        // Get pair token address, creating the pair if it doesn't exist
        address pairToken = getPair[tokenA][tokenB];
        if (pairToken == address(0)) {
            pairToken = this.createPair(tokenA, tokenB);
        }
        
        // Sort tokens to get the correct pair ordering
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        // Map amounts to sorted order
        uint256 amount0Desired = tokenA == token0 ? amountADesired : amountBDesired;
        uint256 amount1Desired = tokenA == token0 ? amountBDesired : amountADesired;
        uint256 amount0Min = tokenA == token0 ? amountAMin : amountBMin;
        uint256 amount1Min = tokenA == token0 ? amountBMin : amountAMin;
        
        // Get pair ID and data
        bytes32 pairId = keccak256(abi.encodePacked(token0, token1));
        Pair storage pair = pairs[pairId];
        
        // Calculate the amounts to be used based on current reserves
        uint256 amount0;
        uint256 amount1;
        
        if (pair.reserve0 == 0 && pair.reserve1 == 0) {
            // First liquidity provision
            amount0 = amount0Desired;
            amount1 = amount1Desired;
        } else {
            // Calculate optimal amounts
            uint256 amount1Optimal = (amount0Desired * pair.reserve1) / pair.reserve0;
            
            if (amount1Optimal <= amount1Desired) {
                if (amount1Optimal < amount1Min) revert Errors.InsufficientAmount();
                amount0 = amount0Desired;
                amount1 = amount1Optimal;
            } else {
                uint256 amount0Optimal = (amount1Desired * pair.reserve0) / pair.reserve1;
                if (amount0Optimal < amount0Min) revert Errors.InsufficientAmount();
                amount0 = amount0Optimal;
                amount1 = amount1Desired;
            }
        }
        
        {
            // Map back to input token order for return values
            amountA = tokenA == token0 ? amount0 : amount1;
            amountB = tokenA == token0 ? amount1 : amount0;
            
            // Check minimum amounts
            if (amountA < amountAMin || amountB < amountBMin) revert Errors.InsufficientAmount();
            
            // Transfer tokens from sender to this contract
            IERC20(tokenA).safeTransferFrom(msg.sender, address(this), amountA);
            IERC20(tokenB).safeTransferFrom(msg.sender, address(this), amountB);
            
            // Calculate liquidity amount
            if (pair.totalSupply == 0) {
                // For first liquidity provision, use geometric mean as liquidity amount
                liquidity = _sqrt(amount0 * amount1);
            } else {
                // For subsequent provisions, use minimum proportional amount
                uint256 liquidity0 = (amount0 * pair.totalSupply) / pair.reserve0;
                uint256 liquidity1 = (amount1 * pair.totalSupply) / pair.reserve1;
                liquidity = liquidity0 < liquidity1 ? liquidity0 : liquidity1;
            }
            
            // Take liquidity fee if applicable
            if (liquidityFee > 0 && pair.totalSupply > 0) {
                uint256 feeAmount = (liquidity * liquidityFee) / 10000;
                if (feeAmount > 0) {
                    liquidity -= feeAmount;
                    // Fee goes to the contract itself, increasing value for all LP providers
                }
            }
        }

        
        // Update reserves and total supply
        pair.reserve0 += amount0;
        pair.reserve1 += amount1;
        pair.totalSupply += liquidity;
        
        emit LiquidityAdded(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
        
        return (amountA, amountB, liquidity);
    }
    
    /**
     * @dev Removes liquidity from a pool
     * @param tokenA First token address
     * @param tokenB Second token address
     * @param liquidity Amount of liquidity tokens to burn
     * @param amountAMin Minimum acceptable amount of first token
     * @param amountBMin Minimum acceptable amount of second token
     * @return amountA Amount of first token received
     * @return amountB Amount of second token received
     */
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin
    ) 
        external
        whenNotPaused
        nonReentrant
        validToken(tokenA)
        validToken(tokenB)
        kycVerified(msg.sender)
        notBlacklisted(msg.sender, tokenA)
        notBlacklisted(msg.sender, tokenB)
        tokenPairExists(tokenA, tokenB)
        returns (uint256 amountA, uint256 amountB)
    {
        if (tokenA == tokenB) revert Errors.InvalidTokenPair();
        if (liquidity == 0) revert Errors.InvalidAmount();
        
        // Sort tokens to get the correct pair ordering
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        // Get pair ID and data
        bytes32 pairId = keccak256(abi.encodePacked(token0, token1));
        Pair storage pair = pairs[pairId];
        
        if (!pair.exists) revert Errors.InvalidTokenPair();
        if (pair.totalSupply == 0) revert Errors.InsufficientAmount();
        
        // Calculate amounts to return proportional to liquidity share
        uint256 amount0 = (liquidity * pair.reserve0) / pair.totalSupply;
        uint256 amount1 = (liquidity * pair.reserve1) / pair.totalSupply;
        
        // Map to input token order for return values
        amountA = tokenA == token0 ? amount0 : amount1;
        amountB = tokenA == token0 ? amount1 : amount0;
        
        // Check minimum amounts
        if (amountA < amountAMin || amountB < amountBMin) revert Errors.InsufficientAmount();
        
        // Update reserves and total supply
        pair.reserve0 -= amount0;
        pair.reserve1 -= amount1;
        pair.totalSupply -= liquidity;
        
        // Transfer tokens to sender
        IERC20(tokenA).safeTransfer(msg.sender, amountA);
        IERC20(tokenB).safeTransfer(msg.sender, amountB);
        
        emit LiquidityRemoved(msg.sender, tokenA, tokenB, amountA, amountB, liquidity);
        
        return (amountA, amountB);
    }
    
    /**
     * @dev Emergency withdrawal of tokens to admin
     * @param token Token address to withdraw
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) 
        external 
        onlyRole(ADMIN_ROLE) 
        validToken(token) 
    {
        if (amount == 0) {
            amount = IERC20(token).balanceOf(address(this));
        }
        
        IERC20(token).safeTransfer(msg.sender, amount);
    }
    
    /**
     * @dev Get all pairs count
     * @return Number of token pairs
     */
    function allPairsLength() external view returns (uint256) {
        return allPairs.length;
    }
    
    /**
     * @dev Get reserves for a token pair
     * @param tokenA First token address
     * @param tokenB Second token address
     * @return reserveA Reserve of first token
     * @return reserveB Reserve of second token
     */
    function getReserves(address tokenA, address tokenB) 
        external 
        view 
        tokenPairExists(tokenA, tokenB)
        returns (uint256 reserveA, uint256 reserveB) 
    {
        // Sort tokens to get the correct pair ordering
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        // Get pair ID and data
        bytes32 pairId = keccak256(abi.encodePacked(token0, token1));
        Pair storage pair = pairs[pairId];
        
        // Map reserves to input token order
        reserveA = tokenA == token0 ? pair.reserve0 : pair.reserve1;
        reserveB = tokenA == token0 ? pair.reserve1 : pair.reserve0;
    }
    
    /**
     * @dev Get quote for output amount based on input
     * @param amountIn Input amount
     * @param reserveIn Reserve of input token
     * @param reserveOut Reserve of output token
     * @return amountOut Expected output amount
     */
    function quote(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) public pure returns (uint256 amountOut) {
        if (amountIn == 0) revert Errors.InvalidAmount();
        if (reserveIn == 0 || reserveOut == 0) revert Errors.InsufficientAmount();
        
        // Calculate fee amount
        uint256 feeAmount = (amountIn * 30) / 10000; // Default 0.3% fee
        uint256 amountInWithFee = amountIn - feeAmount;
        
        // Calculate amount out using constant product formula
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
    }
    
    /**
     * @dev Get expected output amount for a swap
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amountIn Input amount
     * @return Expected output amount
     */
    function getAmountOut(address tokenIn, address tokenOut, uint256 amountIn) 
        external 
        view 
        tokenPairExists(tokenIn, tokenOut)
        returns (uint256) 
    {
        // Sort tokens to get the correct pair ordering
        (address token0, address token1) = tokenIn < tokenOut ? (tokenIn, tokenOut) : (tokenOut, tokenIn);
        
        // Get pair ID and data
        bytes32 pairId = keccak256(abi.encodePacked(token0, token1));
        Pair storage pair = pairs[pairId];
        
        // Determine which token is being swapped in
        bool isToken0In = tokenIn == token0;
        
        // Get reserves
        uint256 reserveIn = isToken0In ? pair.reserve0 : pair.reserve1;
        uint256 reserveOut = isToken0In ? pair.reserve1 : pair.reserve0;
        
        // Calculate fee amount
        uint256 feeAmount = (amountIn * swapFee) / 10000;
        uint256 amountInWithFee = amountIn - feeAmount;
        
        return (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);
    }
    
    function execute(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) 
        external
        returns (uint256)
    {
        return this.swap(tokenIn, tokenOut, amountIn, amountOutMin);
    }
    
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @dev Square root function, uses Babylonian method
     * @dev See https://ethereum.stackexchange.com/questions/2910/can-i-square-root-in-solidity
     * @param y Value to get square root of
     * @return Square root of y
     */
    function _sqrt(uint256 y) internal pure returns (uint256) {
        if (y > 3) {
            uint256 z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
            return z;
        } else if (y != 0) {
            return 1;
        } else {
            return 0;
        }
    }
}
