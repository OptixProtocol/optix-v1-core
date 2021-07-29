pragma solidity ^0.8.6;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/utils/SafeERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/ERC721.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/AccessControl.sol";

import "https://github.com/Uniswap/uniswap-v2-periphery/blob/master/contracts/interfaces/IUniswapV2Router02.sol";
import "https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/interfaces/IUniswapV2Pair.sol";
import "https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/interfaces/IUniswapV2Factory.sol";

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
    function getProtocolFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint poolId, IOracle oracle) external view returns (uint256);
    function getStrikeFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint poolId, IOracle oracle) external pure returns (uint256);
    function getPeriodFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint poolId, IOracle oracle) external view returns (uint256);
    function getBalanceUtilisationFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint poolId, IOracle oracle) external view returns (uint256);
    function getPoolFee(uint256 period, uint256 optionSize, uint256 strike, uint256 currentPrice, IOptions.OptionType optionType, uint poolId, IOracle oracle) external view returns (uint256);
    struct Fees {
        uint256 total;
        uint256 protocolFee;
        uint256 strikeFee;
        uint256 periodFee;
        uint256 balanceUtilisationFee;
        uint256 poolFee;
    }
}

interface IOptions {
    event Create(
        uint256 indexed id,
        address indexed account,
        uint256 indexed marketId,
        uint256 protocolFee,
        uint256 totalFee
    );

    event Exercise(uint256 indexed optionId, uint marketId, uint256 profit);
    event Expire(uint256 indexed optionId, uint marketId, uint256 premium);
    enum State {Inactive, Active, Exercised, Expired}
    enum OptionType {Invalid, Put, Call}

    struct Option  {
        State state;
        address payable holder;
        uint256 strike;
        uint256 optionSize;
        uint256 lockedAmount;
        uint256 premium;
        uint256 expiration;
        OptionType optionType;
        uint256 marketId;
    }

    function options(uint) external view returns (
        State state,
        address payable holder,
        uint256 strike,
        uint256 optionSize,
        uint256 lockedAmount,
        uint256 premium,
        uint256 expiration,
        OptionType optionType,
        uint256 marketId
    );
    
    struct LockedLiquidity { 
        uint amount; 
        uint premium; 
        bool locked; 
        uint poolId; 
        IOptions.OptionType optionType; 
    }
}
