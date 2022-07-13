// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
import "../interfaces/Interfaces.sol"; 

contract UniswapV2Factory is IUniswapV2Factory {
    address public feeTo;
    address public feeToSetter;

    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;


    constructor(address _feeToSetter) public {
    }

    function allPairsLength() external view returns (uint) {
        return 0;
    }

    function createPair(address tokenA, address tokenB) external returns (address pair) {
        return address(0);
    }


    function setFeeTo(address _feeTo) external {

    }

    function setFeeToSetter(address _feeToSetter) external {
    }
}