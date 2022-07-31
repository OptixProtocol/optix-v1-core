pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/ERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";
// import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";

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
    enum BoolState {FalseMutable, TrueMutable, FalseImmutable, TrueImmutable}
    enum SetVariableType {VaultOwner,VaultFeeRecipient,GrantVaultOperatorRole,RevokeVaultOperatorRole,GrantLPWhitelistRole,RevokeLPWhitelistRole, GrantBuyerWhitelistRole,RevokeBuyerWhitelistRole,
    VaultFeeCalc, IpfsHash, ReadOnly, MaxInvest, WithdrawDelayPeriod, LPWhitelistOnly, BuyerWhitelistOnly, CollateralizationRatio, OracleWhitelisted, CollateralTokenWhitelisted, CreateVaultIsPermissionless, OracleIsPermissionless, CollateralTokenIsPermissionless, ProtocolFeeCalc,
    Referrals,TokenPairWhitelisted,SwapServiceWhitelisted,CreateVaultWhitelisted, ProtocolFee, ProtocolFeeRecipient, AutoExercisePeriod, WithdrawDelayPeriodLocked, OracleEnabledLocked, VaultFee}


    event SetVaultBool(address indexed byAccount, SetVariableType indexed eventType, uint indexed vaultId, bool from, bool to);
    event SetVaultBoolState(address indexed byAccount, SetVariableType indexed eventType, uint indexed vaultId, BoolState from, BoolState to);
    event SetVaultAddress(address indexed byAccount, SetVariableType indexed eventType, uint indexed vaultId, address from, address to);
    event SetVaultUInt(address indexed byAccount, SetVariableType indexed eventType, uint indexed vaultId, uint256 from, uint256 to);

    event SetGlobalBool(address indexed byAccount, SetVariableType indexed eventType, bool from, bool to);
    event SetGlobalInt(address indexed byAccount, SetVariableType indexed eventType, uint256 from, uint256 to);
    event SetGlobalBoolState(address indexed byAccount, SetVariableType indexed eventType, BoolState from, BoolState to);
    event SetGlobalAddress(address indexed byAccount, SetVariableType indexed eventType, address from, address to);
    event SetGlobalAddressPair(address indexed byAccount, SetVariableType indexed eventType, address a1, address a2, bool from, bool to);
    event SetGlobalAddressPairBoolState(address indexed byAccount, SetVariableType indexed eventType, address a1, address a2, BoolState from, BoolState to);

    struct Option  {
        State state;
        address holder;
        uint256 strike;
        uint256 optionSize;
        uint256 lockedAmount;
        Fees premium;
        uint256 expiration;
        OptionType optionType;
        uint256 vaultId;
        IOracle oracle;
        address referredBy;
    }

    struct LockedCollateral { 
        uint optionSize; 
        Fees premium; 
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
    event CreateVault(uint indexed vaultId, IOracle oracle, IERC20 collateralToken, address vault);
    event Provide(address indexed account, uint vaultId, uint256 amount, uint256 mintTokens, bool mint);
    event Withdraw(address indexed account, uint vaultId, uint amountA, uint256 burnTokens, bool burn);
    event Lock(uint indexed optionId, uint256 optionSize);
    event Unlock(uint indexed optionId);
    event VaultProfit(uint indexed optionId, uint vaultId, uint amount);
    event VaultLoss(uint indexed optionId, uint vaultId, uint amount);
    event UpdateOracle(IOracle indexed oracle, uint indexed vaultId, bool enabled, IERC20 collateralToken, uint8 decimals, string description); 


    event CreateOption(uint256 indexed optionId, address indexed holder, uint256 period, uint256 optionSize, uint256 strike, IStructs.OptionType optionType, uint256 indexed vaultId, IOracle oracle, IStructs.Fees fees, uint256 totalPremium, address referrer);
    event Exercise(uint256 indexed optionId, uint vaultId, uint256 profit);
    event Expire(uint256 indexed optionId, uint vaultId, uint256 premium);
    event TransferOption(uint256 indexed optionId, address from, address to);
}
