// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "src/interfaces/IBlockVirtualGovernance.sol";
import "src/rwaPriceFeed.sol";
import "src/library/Errors.sol";

/**
 * @title VirtualVault
 * @dev RWA token vault with market making support based on Balancer style
 */
contract VirtualVault is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ERC20Upgradeable {
    using SafeERC20 for IERC20;

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MARKET_MAKER_ROLE = keccak256("MARKET_MAKER_ROLE");
    bytes32 public constant PRICE_REPORTER_ROLE = keccak256("PRICE_REPORTER_ROLE");
    
    // State variables
    IBlockVirtualGovernance public governance;
    BlockVirtualPriceFeed public priceFeed;
    IERC20 public asset;
    
    // Fees and Limits
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public swapFee = 30; // 0.3% default swap fee
    uint256 public totalFees;
    uint256 public maxFee = 1000; // 10% default max fee
    uint256 public maxSlippage = 200; // 2% default max slippage
    
    // Liquidity Providers
    mapping(address => bool) public isLiquidityProvider;
    address[] public liquidityProviders;
    
    // Price Data
    uint256 public lastPriceTimestamp;
    
    // Events
    event Deposit(address indexed liquidityProvider, uint256 assets, uint256 shares);
    event Withdraw(address indexed liquidityProvider, uint256 assets, uint256 shares);
    event SwapExecuted(
        address indexed fromVault,
        address indexed toVault,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );
    event FeesDistributed(uint256 totalFees);
    event SlippageUpdated(uint256 newSlippage);
    event MaxFeeUpdated(uint256 newMaxFee);
    event SwapFeeUpdated(uint256 newSwapFee);
    event LiquidityProviderAdded(address indexed provider);
    event LiquidityProviderRemoved(address indexed provider);
    
    modifier whenNotPaused() {
        if (governance.isVaultPaused(address(this))) revert Errors.VaultPaused();
        _;
    }
    
    modifier onlyValidAmount(uint256 amount) {
        if (amount == 0) revert Errors.InvalidAmount();
        _;
    }
    
    modifier onlyCompliantUser(address user) {
        _checkCompliance(user);
        _;
    }
    
    modifier validAddress(address addr) {
        if (addr == address(0)) revert Errors.ZeroAddress();
        _;
    }
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @dev Initializes the vault contract
     * @param _governance Address of the governance contract
     * @param _priceFeed Address of the price feed contract
     * @param _asset Address of the RWA token
     * @param name Vault share token name
     * @param symbol Vault share token symbol
     */
    function initialize(
        address _governance,
        address _priceFeed,
        address _asset,
        string memory name,
        string memory symbol
    ) public initializer {
        if (_governance == address(0)) revert Errors.ZeroAddress();
        if (_priceFeed == address(0)) revert Errors.ZeroAddress();
        if (_asset == address(0)) revert Errors.ZeroAddress();
        
        __AccessControl_init();
        __ReentrancyGuard_init();
        __ERC20_init(name, symbol);
        
        governance = IBlockVirtualGovernance(_governance);
        priceFeed = BlockVirtualPriceFeed(_priceFeed);
        asset = IERC20(_asset);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MARKET_MAKER_ROLE, msg.sender);
        _grantRole(PRICE_REPORTER_ROLE, msg.sender);
        
        // Initialize state
        lastPriceTimestamp = block.timestamp;
    }
    
    /**
     * @dev Checks compliance for user
     * @param user User address to check
     */
    function _checkCompliance(address user) internal view {
        if (user == address(0)) revert Errors.ZeroAddress();
        if (!governance.getKycStatus(user)) revert Errors.UnauthorizedKycStatus();
        if (!governance.isFromSupportedCountry(user)) revert Errors.UnauthorizedCountryUser();
    }
    
    /**
     * @dev Add a liquidity provider
     * @param provider Address of the provider to add
     */
    function addLiquidityProvider(address provider) 
        external 
        onlyRole(ADMIN_ROLE) 
        validAddress(provider)
    {
        if (isLiquidityProvider[provider]) return; // Already a provider
        
        isLiquidityProvider[provider] = true;
        liquidityProviders.push(provider);
        _grantRole(MARKET_MAKER_ROLE, provider);
        
        emit LiquidityProviderAdded(provider);
    }
    
    /**
     * @dev Remove a liquidity provider
     * @param provider Address of the provider to remove
     */
    function removeLiquidityProvider(address provider) 
        external 
        onlyRole(ADMIN_ROLE) 
        validAddress(provider)
    {
        if (!isLiquidityProvider[provider]) return; // Not a provider
        
        isLiquidityProvider[provider] = false;
        _revokeRole(MARKET_MAKER_ROLE, provider);
        
        // Remove from array
        for (uint256 i = 0; i < liquidityProviders.length; i++) {
            if (liquidityProviders[i] == provider) {
                liquidityProviders[i] = liquidityProviders[liquidityProviders.length - 1];
                liquidityProviders.pop();
                break;
            }
        }
        
        emit LiquidityProviderRemoved(provider);
    }
    
    /**
     * @dev Deposit RWA tokens into the vault and receive shares
     * @param assets Amount of RWA tokens to deposit
     * @return shares Amount of shares received
     */
    function deposit(uint256 assets) 
        external 
        whenNotPaused 
        onlyRole(MARKET_MAKER_ROLE) 
        onlyValidAmount(assets) 
        onlyCompliantUser(msg.sender) 
        returns (uint256 shares) 
    {
        // Calculate shares to mint
        uint256 totalAssetsBefore = asset.balanceOf(address(this));
        if (totalSupply() == 0) {
            shares = assets;
        } else {
            shares = (assets * totalSupply()) / totalAssetsBefore;
        }
        
        // Ensure shares calculation didn't result in 0 shares
        if (shares == 0) revert Errors.InsufficientAmount();
        
        // Transfer assets from sender to vault
        asset.safeTransferFrom(msg.sender, address(this), assets);
        
        // Verify the transfer succeeded by checking balance change
        uint256 totalAssetsAfter = asset.balanceOf(address(this));
        if (totalAssetsAfter != totalAssetsBefore + assets) revert Errors.TransferFailed();
        
        // Mint shares to sender
        _mint(msg.sender, shares);
        
        // Add sender as liquidity provider if not already
        if (!isLiquidityProvider[msg.sender]) {
            isLiquidityProvider[msg.sender] = true;
            liquidityProviders.push(msg.sender);
        }
        
        emit Deposit(msg.sender, assets, shares);
        return shares;
    }
    
    /**
     * @dev Withdraw RWA tokens from the vault using shares
     * @param shares Amount of shares to burn
     * @return assets Amount of RWA tokens received
     */
    function redeem(uint256 shares) 
        external 
        whenNotPaused 
        onlyRole(MARKET_MAKER_ROLE) 
        onlyValidAmount(shares) 
        onlyCompliantUser(msg.sender) 
        returns (uint256 assets) 
    {
        // Check user has enough shares
        if (balanceOf(msg.sender) < shares) revert Errors.InsufficientBalance();
        
        // Calculate assets to withdraw
        uint256 totalAssetsBefore = asset.balanceOf(address(this));
        assets = (shares * totalAssetsBefore) / totalSupply();
        
        // Ensure assets calculation didn't result in 0 assets
        if (assets == 0) revert Errors.InsufficientAmount();
        
        // Burn shares from sender
        _burn(msg.sender, shares);
        
        // Transfer assets to sender
        asset.safeTransfer(msg.sender, assets);
        
        // If balance is now 0, remove from liquidity providers
        if (balanceOf(msg.sender) == 0) {
            isLiquidityProvider[msg.sender] = false;
            for (uint256 i = 0; i < liquidityProviders.length; i++) {
                if (liquidityProviders[i] == msg.sender) {
                    liquidityProviders[i] = liquidityProviders[liquidityProviders.length - 1];
                    liquidityProviders.pop();
                    break;
                }
            }
        }
        
        emit Withdraw(msg.sender, assets, shares);
        return assets;
    }
    
    /**
     * @dev Execute a cross-vault swap with slippage protection
     * @param toVault Destination vault address
     * @param amountIn Amount of RWA tokens to swap
     * @param minAmountOut Minimum amount to receive (slippage protection)
     * @return amountOut Amount of RWA tokens received
     */
    function executeSwap(
        address toVault,
        uint256 amountIn,
        uint256 minAmountOut
    ) 
        external 
        whenNotPaused 
        nonReentrant 
        onlyValidAmount(amountIn) 
        onlyCompliantUser(msg.sender) 
        validAddress(toVault)
        returns (uint256 amountOut) 
    {
        if (toVault == address(this)) revert Errors.InvalidAddress();
        
        // Check if destination is a valid vault
        if (!_isVault(toVault)) revert Errors.InvalidVault();
        
        // Calculate fee
        uint256 fee = (amountIn * swapFee) / FEE_DENOMINATOR;
        uint256 amountInAfterFee = amountIn - fee;
        
        // Get expected output amount using price feed
        uint256 expectedAmountOut = _getExpectedAmountOut(toVault, amountInAfterFee);
        
        // Ensure price feed has valid data
        if (expectedAmountOut == 0) revert Errors.InvalidPrice();
        
        // Calculate minimum allowed amount based on slippage
        uint256 minAllowedAmountOut = (expectedAmountOut * (FEE_DENOMINATOR - maxSlippage)) / FEE_DENOMINATOR;
        
        // Ensure minimum amount is within slippage tolerance
        if (minAmountOut < minAllowedAmountOut) {
            minAmountOut = minAllowedAmountOut;
        }
        
        // Transfer assets from sender to this vault
        asset.safeTransferFrom(msg.sender, address(this), amountIn);
        
        // Add fee to total fees
        totalFees += fee;
        
        // Approve destination vault to spend assets
        asset.approve(toVault, 0); // Clear previous allowance
        asset.approve(toVault, amountInAfterFee);
        
        // Execute swap with destination vault
        amountOut = VirtualVault(toVault).swapFromVault(address(this), msg.sender, amountInAfterFee, minAmountOut);
        
        // Verify swap output amount meets minimum requirements
        if (amountOut < minAmountOut) revert Errors.SlippageTooHigh();
        
        emit SwapExecuted(address(this), toVault, msg.sender, amountIn, amountOut, fee);
        return amountOut;
    }
    
    /**
     * @dev Internal function to handle swaps from other vaults
     * @param fromVault Source vault address
     * @param recipient Final recipient of the tokens
     * @param amountIn Amount of RWA tokens received from source vault
     * @param minAmountOut Minimum amount to send to recipient
     * @return amountOut Amount of tokens sent to recipient
     */
    function swapFromVault(
        address fromVault,
        address recipient,
        uint256 amountIn,
        uint256 minAmountOut
    ) 
        external 
        nonReentrant 
        validAddress(fromVault)
        validAddress(recipient)
        onlyValidAmount(amountIn)
        returns (uint256 amountOut) 
    {
        // Only other vaults can call this function
        if (!_isVault(msg.sender)) revert Errors.UnauthorizedRole(msg.sender);
        
        // Check if caller matches the fromVault parameter
        if (msg.sender != fromVault) revert Errors.InvalidVault();
        
        // Calculate amount to send to recipient based on price feed
        amountOut = _getAmountOutForSwap(fromVault, amountIn);
        
        // Ensure price calculation is valid
        if (amountOut == 0) revert Errors.InvalidPrice();
        
        // Check slippage
        if (amountOut < minAmountOut) revert Errors.SlippageTooHigh();
        
        // Check if vault has enough balance
        if (asset.balanceOf(address(this)) < amountOut) revert Errors.InsufficientBalance();
        
        // Execute transfer to recipient
        asset.safeTransfer(recipient, amountOut);
        
        return amountOut;
    }
    
    /**
     * @dev Distribute accumulated fees to liquidity providers
     */
    function distributeFees() external nonReentrant {
        if (totalFees == 0) revert Errors.InsufficientBalance();
        
        uint256 fees = totalFees;
        totalFees = 0;
        
        uint256 totalShares = totalSupply();
        if (totalShares == 0) return; // No one to distribute to
        
        // Distribute to all liquidity providers based on their share
        for (uint256 i = 0; i < liquidityProviders.length; i++) {
            address provider = liquidityProviders[i];
            uint256 providerShares = balanceOf(provider);
            
            if (providerShares > 0) {
                uint256 providerFees = (fees * providerShares) / totalShares;
                if (providerFees > 0) {
                    asset.safeTransfer(provider, providerFees);
                }
            }
        }
        
        emit FeesDistributed(fees);
    }
    
    /**
     * @dev Set swap fee
     * @param _fee New fee in basis points (1 = 0.01%)
     */
    function setSwapFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
        if (_fee > maxFee) revert Errors.ExceedsLimit(_fee, maxFee);
        swapFee = _fee;
        emit SwapFeeUpdated(_fee);
    }
    
    /**
     * @dev Set maximum allowed fee
     * @param _maxFee New maximum fee in basis points (1 = 0.01%)
     */
    function setMaxFee(uint256 _maxFee) external onlyRole(ADMIN_ROLE) {
        if (_maxFee > 3000) revert Errors.ExceedsLimit(_maxFee, 3000); // Absolute maximum 30%
        maxFee = _maxFee;
        emit MaxFeeUpdated(_maxFee);
    }
    
    /**
     * @dev Set maximum allowed slippage
     * @param _slippage New slippage in basis points (1 = 0.01%)
     */
    function setMaxSlippage(uint256 _slippage) external onlyRole(ADMIN_ROLE) {
        if (_slippage > 2000) revert Errors.ExceedsLimit(_slippage, 2000); // Max 20%
        maxSlippage = _slippage;
        emit SlippageUpdated(_slippage);
    }
    
    /**
     * @dev Get expected amount out based on price feed
     */
    function _getExpectedAmountOut(address toVault, uint256 amountIn) internal view returns (uint256) {
        address fromToken = address(asset);
        address toToken = address(VirtualVault(toVault).asset());
        
        // Get prices from price feed
        uint256 fromPrice = priceFeed.getLatestPrice(fromToken);
        uint256 toPrice = priceFeed.getLatestPrice(toToken);
        
        // Verify prices are valid
        if (fromPrice == 0 || toPrice == 0) return 0;
        
        // Calculate equivalent value
        return (amountIn * fromPrice) / toPrice;
    }
    
    /**
     * @dev Get actual amount out for a swap
     */
    function _getAmountOutForSwap(address fromVault, uint256 amountIn) internal view returns (uint256) {
        // In a real implementation, you might want to add additional logic here
        // such as dynamic pricing based on vault balances
        return _getExpectedAmountOut(fromVault, amountIn);
    }
    
    /**
     * @dev Check if an address is a registered vault
     */
    function _isVault(address addr) internal view returns (bool) {
        if (addr == address(0)) return false;
        
        try VirtualVault(addr).governance() returns (IBlockVirtualGovernance _governance) {
            return address(_governance) == address(governance);
        } catch {
            return false;
        }
    }
    
    /**
     * @dev Get total assets in the vault
     * @return Total assets
     */
    function totalAssets() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }
    
    /**
     * @dev Convert assets to shares
     * @param assets Amount of assets
     * @return shares Amount of shares
     */
    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 supply = totalSupply();
        if (supply == 0) return assets;
        
        uint256 _totalAssets = totalAssets();
        if (_totalAssets == 0) return 0;
        
        return (assets * supply) / _totalAssets;
    }
    
    /**
     * @dev Convert shares to assets
     * @param shares Amount of shares
     * @return assets Amount of assets
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        uint256 supply = totalSupply();
        if (supply == 0 || shares == 0) return 0;
        
        return (shares * totalAssets()) / supply;
    }
    
    /**
     * @dev Get all liquidity providers
     * @return Array of liquidity provider addresses
     */
    function getLiquidityProviders() external view returns (address[] memory) {
        return liquidityProviders;
    }
    
    /**
     * @dev Get the number of liquidity providers
     * @return Number of liquidity providers
     */
    function getLiquidityProviderCount() external view returns (uint256) {
        return liquidityProviders.length;
    }
} 