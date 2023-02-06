// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.13;
import "./Interfaces.sol";

interface ISimpleSeller {
  function callFactor ( uint256, address, uint256 ) external view returns ( uint256 );
  function callFactorLength ( uint256 vaultId, address oracle ) external view returns ( uint256 );
  function callPeriods ( uint256, address, uint256 ) external view returns ( uint256 );
  function callPeriodsLength ( uint256 vaultId, address oracle ) external view returns ( uint256 );
  function callPrices ( uint256, address, uint256, uint256 ) external view returns ( uint256 strike, uint256 fee );
  function callPricesLength ( uint256 vaultId, address oracle, uint256 period ) external view returns ( uint256 );
  function deletePricePoints ( uint256 vaultId, address oracle ) external;
  function dutchAuctionStartMultiplier ( uint256 ) external view returns ( uint256 );
  function dutchAuctionStartTime ( uint256 ) external view returns ( uint256 );
  function dutchAuctionWindow ( uint256 ) external view returns ( uint256 );
  function factory (  ) external view returns ( address );
  function getFactor ( uint256 vaultId, uint256[] memory factorArray, uint256 optionSize ) external view returns ( uint256 );
  function getFees ( IStructs.InputParams memory inParams ) external view returns ( IStructs.Fees memory fees_ );
  function putFactor ( uint256, address, uint256 ) external view returns ( uint256 );
  function putFactorLength ( uint256 vaultId, address oracle ) external view returns ( uint256 );
  function putPeriods ( uint256, address, uint256 ) external view returns ( uint256 );
  function putPeriodsLength ( uint256 vaultId, address oracle ) external view returns ( uint256 );
  function putPrices ( uint256, address, uint256, uint256 ) external view returns ( uint256 strike, uint256 fee );
  function putPricesLength ( uint256 vaultId, address oracle, uint256 period ) external view returns ( uint256 );
  function setDutchAuctionParams ( uint256 vaultId, uint256 _dutchAuctionStartTime, uint256 _dutchAuctionWindow, uint256 _dutchAuctionStartMultiplier ) external;
  function setFactor ( uint256 vaultId, address oracle, uint8 optionType, uint256[] memory factors ) external;
  function setPricePoints ( uint256 vaultId, address oracle, uint8 optionType, uint256[] memory periods, uint256[] memory strikes, uint256[] memory fees ) external;
}
