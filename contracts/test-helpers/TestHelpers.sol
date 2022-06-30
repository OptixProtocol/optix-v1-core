pragma solidity 0.8.13;

/**
 *  * SPDX-License-Identifier: GPL-3.0-or-later
 */
 

import "../interfaces/Interfaces.sol"; 
 
// contract Oracle is IOracle {
//       function decimals()
//     external
//     view
//     override 
//     returns (
//       uint8
//     ){}

//   function description()
//     external
//     view
//     override 
//     returns (
//       string memory
//     ){}

//   function latestAnswer()
//     external
//     view
//     override 
//     returns (
//       uint256
//     ){

//     }
// }

// contract FakeUSDC is ERC20("Fake USDC", "USDC") {
//     function mintTo(address account, uint256 amount) public {
//         _mint(account, amount);
//     }

//     function mint(uint256 amount) public {
//         _mint(msg.sender, amount);
//     }
    
//     function decimals() public view virtual override returns (uint8) {
//         return 6;
//     }
// }

   

contract TestCalc {
    
    uint256 public utilisation = 0;
    uint256 public putRatio = 5000;
    uint256 public callRatio = 5000;

    function setVals(uint256 _utilisation,uint256 _putRatio,uint256 _callRatio) public {
        utilisation = _utilisation;
        putRatio = _putRatio;
        callRatio = _callRatio;
    }  
        
    
    //(utilisation^2/4) * (put or call^2/4) / 62500000000
    function getBalanceUtilisationFee(uint256 period,
        uint256 optionSize,
        uint256 strike,
        uint256 currentPrice,
        IStructs.OptionType optionType,
        uint poolId,
        IOracle oracle
    )
                external
        view
        returns (uint256 fee)
    {
        if( optionType == IStructs.OptionType.Call ){
            return (utilisation*utilisation/4) * (callRatio*callRatio/4) / 62500000000;
        }
        if( optionType == IStructs.OptionType.Put ){ 
            return (utilisation*utilisation/4) * (putRatio*putRatio/4) / 62500000000;
        }        
    }
}