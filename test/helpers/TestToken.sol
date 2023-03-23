// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "solmate/tokens/ERC20.sol";


contract TestToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("TestToken", "TT", 18) {
        // _mint(msg.sender, initialSupply);
    }

    function mint(address to, uint256 amount) external virtual {
        _mint(to, amount);
    }
}
