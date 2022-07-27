pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 
import "../interfaces/Interfaces.sol";

library OptionsLib {

    function boolStateIsTrue(IStructs.BoolState value) internal view returns (bool){   
        return (value==IStructs.BoolState.TrueMutable || value==IStructs.BoolState.TrueImmutable);
    }

    function boolStateIsMutable(IStructs.BoolState value) internal view returns (bool){
        return (value==IStructs.BoolState.TrueMutable || value==IStructs.BoolState.FalseMutable);
    }
}