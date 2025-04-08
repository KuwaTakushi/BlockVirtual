// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "src/interfaces/IBlockVirtualGovernance.sol";
import "src/rwaPriceFeed.sol";
import "src/library/Errors.sol";

/**
 * @title VirtualVault
 * @dev RWA token vault with market making support
 */
contract VirtualVault is Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable, ERC20Upgradeable {

    // Roles
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MARKET_MAKER_ROLE = keccak256("MARKET_MAKER_ROLE");
    
    // State variables
    IBlockVirtualGovernance public governance;
    BlockVirtualPriceFeed public priceFeed;
    IERC20 public asset;
    
    // Fees
    uint256 public constant FEE_DENOMINATOR = 10000;
    uint256 public swapFee = 30; // 0.3% default swap fee
    uint256 public totalFees;    // 累计费用
    
    // Events
    event Deposit(address indexed marketMaker, uint256 assets, uint256 shares);
    event Withdraw(address indexed marketMaker, uint256 assets, uint256 shares);
    event SwapExecuted(
        address indexed fromVault,
        address indexed toVault,
        address indexed user,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee
    );
    event FeesDistributed(uint256 totalFees);
    
    modifier whenNotPaused() {
        if (governance.isVaultPaused(address(this))) revert Errors.VaultPaused();
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
    }
    
    /**
     * @dev Deposit RWA tokens into the vault and receive shares
     * @param assets Amount of RWA tokens to deposit
     * @return shares Amount of shares received
     */
    function deposit(uint256 assets) external whenNotPaused onlyRole(MARKET_MAKER_ROLE) returns (uint256 shares) {
        if (assets == 0) revert Errors.InvalidAmount();
        
        if (totalSupply() == 0) {
            shares = assets;
        } else {
            shares = (assets * totalSupply()) / asset.balanceOf(address(this));
        }
        
        asset.transferFrom(msg.sender, address(this), assets);
        _mint(msg.sender, shares);
        
        emit Deposit(msg.sender, assets, shares);
        return shares;
    }
    
    /**
     * @dev Withdraw RWA tokens from the vault using shares
     * @param shares Amount of shares to burn
     * @return assets Amount of RWA tokens received
     */
    function redeem(uint256 shares) external whenNotPaused onlyRole(MARKET_MAKER_ROLE) returns (uint256 assets) {
        if (shares == 0) revert Errors.InvalidAmount();
        
        assets = (shares * asset.balanceOf(address(this))) / totalSupply();
        if (assets == 0) revert Errors.InsufficientBalance();
        
        _burn(msg.sender, shares);
        asset.transfer(msg.sender, assets);
        
        emit Withdraw(msg.sender, assets, shares);
        return assets;
    }
    
    /**
     * @dev Execute a cross-vault swap
     * @param toVault Destination vault address
     * @param amountIn Amount of RWA tokens to swap
     * @return amountOut Amount of RWA tokens received
     */
    function executeSwap(
        address toVault,
        uint256 amountIn
    ) external whenNotPaused nonReentrant returns (uint256 amountOut) {
        if (amountIn == 0) revert Errors.InvalidAmount();
        if (toVault == address(this)) revert Errors.ZeroAddress();
        if (!governance.isFromSupportedCountry(msg.sender)) revert Errors.UnauthorizedCountryUser();
        if (!governance.getKycStatus(msg.sender)) revert Errors.UnauthorizedKycStatus();
        
        uint256 fee = (amountIn * swapFee) / FEE_DENOMINATOR;
        uint256 amountInAfterFee = amountIn - fee;
        totalFees += fee;
        
        asset.transferFrom(msg.sender, address(this), amountIn);
        asset.approve(toVault, amountInAfterFee);
        amountOut = VirtualVault(toVault).executeSwap(address(this), amountInAfterFee);
        asset.transfer(msg.sender, amountOut);
        
        emit SwapExecuted(address(this), toVault, msg.sender, amountIn, amountOut, fee);
        return amountOut;
    }
    
    /**
     * @dev Distribute accumulated fees to market makers
     */
    function distributeFees() external nonReentrant {
        if (totalFees == 0) revert Errors.InsufficientBalance();
        
        uint256 fees = totalFees;
        totalFees = 0;
        
        uint256 totalShares = totalSupply();
        for (uint256 i = 0; i < totalShares; i++) {
            address marketMaker = _getMarketMaker(i);
            if (marketMaker != address(0)) {
                uint256 shareFees = (fees * balanceOf(marketMaker)) / totalShares;
                asset.transfer(marketMaker, shareFees);
            }
        }
        
        emit FeesDistributed(fees);
    }
    
    /**
     * @dev Set swap fee
     * @param _fee New fee in basis points (1 = 0.01%)
     */
    function setSwapFee(uint256 _fee) external onlyRole(ADMIN_ROLE) {
        if (_fee > 1000) revert Errors.ExceedsLimit(_fee, 1000); // Max 10%
        swapFee = _fee;
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
        if (totalSupply() == 0) return assets;
        return (assets * totalSupply()) / totalAssets();
    }
    
    /**
     * @dev Convert shares to assets
     * @param shares Amount of shares
     * @return assets Amount of assets
     */
    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        if (totalSupply() == 0) return 0;
        return (shares * totalAssets()) / totalSupply();
    }
    
    /**
     * @dev Get market maker at index
     * @param index Share index
     * @return marketMaker Market maker address
     */
    function _getMarketMaker(uint256 index) internal view returns (address marketMaker) {
        // Implementation depends on how market makers are tracked
        // This is a placeholder for the actual implementation
        return address(0);
    }
} 