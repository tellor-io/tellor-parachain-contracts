// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../src/Parachain.sol";

contract TestParachain is Parachain {
    constructor(address _registry) Parachain(_registry) {}

    function reportStakeDepositedExternal(
        IRegistry.Parachain memory _parachain,
        address _staker,
        bytes calldata _reporter,
        uint256 _amount
    ) external {
        reportStakeDeposited(_parachain, _staker, _reporter, _amount);
    }
}