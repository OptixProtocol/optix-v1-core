// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.13;
import "./interfaces/Interfaces.sol";

/// @title Options Health Check
/// @author dannydoritoeth
/// @notice Abstract interface that can be used to check edge cases and block creation of options.
abstract contract OptionsHealthCheck  {

     /// @notice Call when creating an option and returns false if the option fails some risk check
     /// @param premium_ the premium calculated for the option in a struct
     /// @param inParams_ the parameters passed to the premium function in a struct
     /// @return Documents the return variables of a contract’s function state variable
     function IsSafeToCreateOption(IStructs.Fees memory premium_,IStructs.InputParams memory inParams_) public virtual returns(bool);
}
