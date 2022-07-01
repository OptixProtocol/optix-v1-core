pragma solidity 0.8.13;

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

interface IStructs {
    struct Fees {
        uint256 total;
        uint256 protocolFee;
        uint256 referFee;
        uint256 intrinsicFee;
        uint256 extrinsicFee;
        uint256 vaultFee;
    }

    enum State {Inactive, Active, Exercised, Expired}
    enum OptionType {Invalid, Put, Call}
    enum SetVariableType {VaultOwner,VaultFeeRecipient,GrantVaultOperatorRole,RevokeVaultOperatorRole,GrantLPWhitelistRole,RevokeLPWhitelistRole,
    VaultFeeCalc, IpfsHash, ReadOnly, MaxInvest, WithdrawDelayPeriod, LPWhitelistOnly, CollateralizationRatio, OracleWhitelisted,ProtocolFeeCalc,
    Referrals}

    event SetVaultBool(address indexed byAccount, SetVariableType indexed eventType, uint indexed vaultId, bool from, bool to);
    event SetVaultAddress(address indexed byAccount, SetVariableType indexed eventType, uint indexed vaultId, address from, address to);
    event SetVaultUInt(address indexed byAccount, SetVariableType indexed eventType, uint indexed vaultId, uint256 from, uint256 to);
    event SetGlobalBool(address indexed byAccount, SetVariableType indexed eventType, bool from, bool to);
    event SetGlobalAddress(address indexed byAccount, SetVariableType indexed eventType, address from, address to);

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

    struct LockedCollateral { 
        uint amount; 
        uint premium; 
        bool locked; 
        uint vaultId; 
        OptionType optionType; 
    }

    struct PricePoint{
        uint256 strike;
        uint256 fee;
    }
}

interface IProtocolFeeCalcs {
    function getProtocolFee(address holder,uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IStructs.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);
    function getReferFee(address holder,uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IStructs.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);
}

interface IFeeCalcs {
    function getIntrinsicFee(address holder, uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IStructs.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);
    function getExtrinsicFee(address holder, uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IStructs.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);
    function getVaultFee(address holder, uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IStructs.OptionType optionType, uint vaultId, IOracle oracle) external view returns (uint256);

}

interface IOptions {
    event CreateVault(uint indexed vaultId, IOracle oracle, IERC20 collateralToken, IERC20 hedgeToken, IUniswapV2Factory swapFactory, IUniswapV2Router02 swapRouter);
    event Provide(address indexed account, uint vaultId, uint256 amount, uint256 mintTokens, bool mint);
    event Withdraw(address indexed account, uint vaultId, uint amountA, uint256 burnTokens, bool burn);
    event Lock(uint indexed optionId, uint256 optionSize);
    event Unlock(uint indexed optionId);
    event VaultProfit(uint indexed optionId, uint vaultId, uint amount);
    event VaultLoss(uint indexed optionId, uint vaultId, uint amount);
    event UpdateOracle(IOracle indexed oracle, uint indexed vaultId, bool enabled, IERC20 collateralToken, IERC20 hedgeToken, uint8 decimals, string description); 


    event CreateOption(uint256 indexed optionId, address indexed holder, uint256 period, uint256 optionSize, uint256 strike, IStructs.OptionType optionType, uint256 indexed vaultId, IOracle oracle, uint256 protocolFee, uint256 vaultFee, uint256 totalPremium, address referrer);
    event Exercise(uint256 indexed optionId, uint vaultId, uint256 profit);
    event Expire(uint256 indexed optionId, uint vaultId, uint256 premium);
    event TransferOption(uint256 indexed optionId, address from, address to);

    event SetDeltaHedge(uint256 indexed vaultId, uint percent, bool _toCollateral);
}
