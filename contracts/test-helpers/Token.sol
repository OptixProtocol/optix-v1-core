// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20 {
    uint8 public retDecimals = 18;

    constructor(string memory _name, uint8 _decimals) ERC20(_name, _name) {
        retDecimals = _decimals;
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }

    function decimals() public view virtual override returns (uint8) {
        return retDecimals;
    }
}
