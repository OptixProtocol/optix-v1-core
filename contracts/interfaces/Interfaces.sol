pragma solidity ^0.8.6;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";


// import "github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
// import "github.com/Uniswap/uniswap-v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol";
// import "github.com/Uniswap/uniswap-v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol";

interface IOracle {

  function decimals()
    external
    view
    returns (
      uint8
    );

  function description()
    external
    view
    returns (
      string memory
    );

  function latestAnswer()
    external
    view
    returns (
      uint256
    );
}


interface IFeeCalcs {
    function getStrikeFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint vaultId, IOracle oracle) external pure returns (uint256);
    function getPeriodFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);
    function getDemandFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);
    function getVaultFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);
    struct Fees {
        uint256 total;
        uint256 protocolFee;
        uint256 referFee;
        uint256 strikeFee;
        uint256 periodFee;
        uint256 demandFee;
        uint256 vaultFee;
    }
}

interface IOptions {
    event CreateOption(uint256 indexed optionId, address indexed holder, uint256 period, uint256 optionSize, uint256 strike, OptionType optionType, uint256 indexed vaultId, IOracle oracle, uint256 protocolFee, uint256 vaultFee, uint256 totalPremium, address referrer);
    event CreateVault(uint indexed vaultId, IOracle oracle, IERC20 _collateralToken, IERC20 _hedgeToken, IUniswapV2Factory _swapFactory, IUniswapV2Router02 _swapRouter);
    event UpdateOracle(IOracle indexed oracle, uint indexed vaultId, bool enabled); 
    event VaultProfit(uint indexed optionId, uint vaultId, uint amount);
    event VaultLoss(uint indexed optionId, uint vaultId, uint amount);
    event Exercise(uint256 indexed optionId, uint vaultId, uint256 profit);
    event Expire(uint256 indexed optionId, uint vaultId, uint256 premium);

    //vaults
    // event CreateMarket(uint indexed marketId, AggregatorV3Interface priceProvider, IERC20 pool);
    // event Profit(uint indexed optionId, IERC20 pool, uint amount);
    // event Loss(uint indexed optionId, IERC20 pool, uint amount);
    event Provide(address indexed account, uint vaultId, uint256 amount, uint256 mintTokens);
    event Withdraw(address indexed account, uint vaultId, uint amountA, uint amountB, uint256 burnTokens);

    enum State {Inactive, Active, Exercised, Expired}
    enum OptionType {Invalid, Put, Call}

    struct Option  {
        State state;
        address holder;
        uint256 strike;
        uint256 optionSize;
        uint256 lockedAmount;
        uint256 premium;
        uint256 expiration;
        OptionType optionType;
        uint256 vaultId;
        IOracle oracle;
        address referredBy;
    }

    // function options(uint) external view returns (
    //     State state,
    //     address payable holder,
    //     uint256 strike,
    //     uint256 optionSize,
    //     uint256 lockedAmount,
    //     uint256 premium,
    //     uint256 expiration,
    //     OptionType optionType,
    //     uint256 vaultId
    // );
    
    struct LockedCollateral { 
        uint amount; 
        uint premium; 
        bool locked; 
        uint vaultId; 
        IOptions.OptionType optionType; 
    }
}
