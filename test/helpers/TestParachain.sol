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

    function reportStakeWithdrawRequestedExternal(
        IRegistry.Parachain memory _parachain,
        bytes memory _account,
        uint256 _amount,
        address _staker
    ) external {
        reportStakeWithdrawRequested(_parachain, _account, _amount, _staker);
    }

    function reportSlashExternal(IRegistry.Parachain memory _parachain, bytes memory _reporter, uint256 _amount)
        external
    {
        reportSlash(_parachain, abi.encodePacked(_reporter), _amount);
    }

    function reportStakeWithdrawnExternal(
        IRegistry.Parachain memory _parachain,
        bytes memory _reporter,
        uint256 _amount
    ) external {
        reportStakeWithdrawn(_parachain, _reporter, _amount);
    }

    function reverseExternal(uint256 input) external pure returns (uint256) {
        return reverse(input);
    }
}
