pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "../interfaces/Interfaces.sol";
import "hardhat/console.sol"; 

library OptionsLib {


    function boolStateIsTrue(uint8 value) internal view returns (bool){   
        return boolStateIsTrue(IStructs.BoolState(value));        
    }


    function boolStateIsTrue(IStructs.BoolState value) internal view returns (bool){   
        return (value==IStructs.BoolState.TrueMutable || value==IStructs.BoolState.TrueImmutable);
    }

    function boolStateIsMutable(IStructs.BoolState value) internal view returns (bool){
        if (uint(value)==0){
            return true;
        }
        return (value==IStructs.BoolState.TrueMutable || value==IStructs.BoolState.FalseMutable);
    }
}