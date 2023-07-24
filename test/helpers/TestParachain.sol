// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../src/Parachain.sol";

contract TestParachain is Parachain {
    uint64 public fakeReportStakeDeposited = 1218085000;
    uint64 public fakeReportStakeWithdrawRequested = 1155113000;
    uint64 public fakeReportStakeWithdrawn = 261856000;
    uint64 public fakeReportVoteTallied = 198884000;
    uint64 public fakeReportVoteExecuted = 323353000;
    uint64 public fakeReportSlash = 1051143000;

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
        reportSlash(_parachain, _reporter, _amount);
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

    function x1External(uint32 _paraId) external pure returns (bytes[] memory) {
        return x1(_paraId);
    }

    function convertWeightToFeeExternal(uint256 overallWeight, uint256 weightToFee) external pure returns (uint256) {
        return convertWeightToFee(overallWeight, weightToFee);
    }

    // exclude contract from coverage report
    function test() public {}
}
