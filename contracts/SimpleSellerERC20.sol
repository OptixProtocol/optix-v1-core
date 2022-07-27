pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */

import "./OptionsVaultFactory.sol";
import "./interfaces/Interfaces.sol";

contract SimpleSellerERC20 is IFeeCalcs, IStructs {

    OptionsVaultFactory public factory;

    mapping(uint => mapping(IOracle => uint256[])) public callPeriods; //vaultId -> oracle -> array of periods
    mapping(uint => mapping(IOracle => mapping (uint256 => IStructs.PricePoint[]))) public callPrices; //vaultId -> oracle -> period -> array of prices at strikes
    mapping(uint => mapping(IOracle => uint256)) public callFactor; //vaultId -> oracle -> 10000 = 100%

    mapping(uint => mapping(IOracle => uint256[])) public putPeriods; 
    mapping(uint => mapping(IOracle => mapping (uint256 => IStructs.PricePoint[]))) public putPrices; 
    mapping(uint => mapping(IOracle => uint256)) public putFactor; 

    constructor(OptionsVaultFactory _factory){
        factory = _factory;
    }

    function getIntrinsicFee(
        address holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        IStructs.OptionType optionType,
        uint vaultId,
        IOracle oracle
    )
        override
        external
        pure
        returns (uint256)
    {
      if (strike < currentPrice && optionType == OptionType.Call)
            return (currentPrice-strike)*1e4/currentPrice;
      if (strike > currentPrice && optionType == OptionType.Put)
            return (strike-currentPrice)*1e4/currentPrice;
      return 0;       
    }


    function getExtrinsicFee(
        address holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike, 
        uint256 currentPrice,
        IStructs.OptionType optionType,
        uint vaultId,
        IOracle oracle
    ) override external view returns (uint256) {
        require (callPeriods[vaultId][oracle].length>0,"No periods for this vault->oracle");
        require (optionType == OptionType.Call || optionType == OptionType.Put,"Must be put or call");
        uint matchPeriod = 0;
        uint256[] memory p;
        uint findStrike = 0;  

        if(optionType == OptionType.Call){
            p = callPeriods[vaultId][oracle];
            if (strike <= currentPrice){
                //ITM: use ATM price
                findStrike = 0;            
            } 
            else{
                findStrike = (strike-currentPrice)*1e4/currentPrice;            
            }
        }

        if(optionType == OptionType.Put){
            p = putPeriods[vaultId][oracle];           
            if (strike >= currentPrice){
                //ITM: use ATM price
                findStrike = 0;
            }else{
                findStrike = (currentPrice-strike)*1e4/currentPrice;
            }
         }

        for(uint i=0; i<p.length; i++){            
             if (period >= p[i]){
                 matchPeriod = p[i];
                 break;
             }
        }

        require (matchPeriod>0,"No matched period");
        uint matchStrike = 0;    
        uint matchFee = 0;
        bool foundMatch = false;
        if(optionType == OptionType.Call){
            for(uint i=0; i<callPrices[vaultId][oracle][matchPeriod].length; i++){ 
                if (callPrices[vaultId][oracle][matchPeriod][i].strike >= findStrike){
                    matchStrike = callPrices[vaultId][oracle][matchPeriod][i].strike;
                    matchFee = callPrices[vaultId][oracle][matchPeriod][i].fee;
                    foundMatch = true;
                    break;
                }
            }

            require (foundMatch,"No matched call strike");
            return matchFee * callFactor[vaultId][oracle] / 1e4;
        }
        if(optionType == OptionType.Put){
            for(uint i=0; i<putPrices[vaultId][oracle][matchPeriod].length; i++){ 
                if (putPrices[vaultId][oracle][matchPeriod][i].strike >= findStrike){
                    matchStrike = putPrices[vaultId][oracle][matchPeriod][i].strike;
                    matchFee = putPrices[vaultId][oracle][matchPeriod][i].fee;                    
                    foundMatch = true;
                    break;
                }
            }
            require (foundMatch,"No matched put strike");  
            return matchFee * putFactor[vaultId][oracle] / 1e4;
        }
        require (true,"No fee calculated");          
    }

    function getVaultFee(
        address holder,
        uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        OptionType optionType,
        uint vaultId,
        IOracle oracle
    )         
        override
        external
        view
        returns (uint256)
    {
        return 100;
    }

    function setFactor(uint vaultId, IOracle oracle, OptionType optionType, uint factor) public {
        factory.vaults(vaultId).isVaultOwnerOrOperator(msg.sender);
        if (optionType == OptionType.Call){
            callFactor[vaultId][oracle] = factor;
        }
        else{
            putFactor[vaultId][oracle] = factor;
        }
    }

    function deletePricePoints(uint vaultId, IOracle oracle, OptionType optionType) public {
        factory.vaults(vaultId).isVaultOwnerOrOperator(msg.sender);    
        delete callPeriods[vaultId][oracle];
        delete putPeriods[vaultId][oracle];
    }

    function pushPricePoints(uint vaultId, IOracle oracle, OptionType optionType, uint[] memory periods, uint[] memory strikes, uint[] memory fees) public {
        require(periods.length>0,"SimpleSeller: must have some price points");
        require(periods.length==strikes.length,"SimpleSeller: periods & strikes lengths must be the same");
        require(periods.length==fees.length,"SimpleSeller: periods & fees lengths must be the same");
        factory.vaults(vaultId).isVaultOwnerOrOperator(msg.sender);

        if (optionType == OptionType.Call){
            delete callPeriods[vaultId][oracle];

            uint lastPeriod = 0;
            for(uint i=0; i<periods.length; i++){
                if (lastPeriod != periods[i]){
                    callPeriods[vaultId][oracle].push(periods[i]);
                    callFactor[vaultId][oracle] = 1e4;
                    lastPeriod = periods[i];
                }
                callPrices[vaultId][oracle][lastPeriod].push(PricePoint(strikes[i],fees[i]));
            }
        }

        if (optionType == OptionType.Put){
            delete putPeriods[vaultId][oracle];

            uint lastPeriod = 0;
            for(uint i=0; i<periods.length; i++){
                if (lastPeriod != periods[i]){
                    putPeriods[vaultId][oracle].push(periods[i]);
                    putFactor[vaultId][oracle] = 1e4;
                    lastPeriod = periods[i];
                }
                putPrices[vaultId][oracle][lastPeriod].push(PricePoint(strikes[i],fees[i]));
            }
        }        
    }
}