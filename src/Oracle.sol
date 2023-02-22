// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TellorFlex} from "lib/tellor/TellorFlex.sol";
import {Parachain} from "./Parachain.sol";

interface iOracle {
    function depositParachainStake(uint32 _paraId, bytes calldata _account, uint256 _amount) external;
    function requestParachainStakeWithdrawal(uint32 _paraId, uint256 _amount) external;
    function confirmParachainStakeWidthrawRequest(uint32 _paraId, address _staker, uint256 _amount) external;
    function withdrawParachainStake(uint32 _paraId, address _staker, uint256 _amount) external;
    function slashParachainReporter(uint32 _paraId, address _reporter, address _recipient) external;
 
}

contract Oracle is Parachain, TellorFlex {
    struct ParachainStakeInfo {
        StakeInfo _stakeInfo;
        bytes _account;
        uint256 _lockedBalanceConfirmed; // the amount confirmed by the parachain. Where is this updated?
    }

    mapping(uint32 => mapping(address => ParachainStakeInfo)) private parachainStakeInfo;

    event NewParachainStaker(uint32 _paraId, address _staker, bytes _account, uint256 _amount);
    event ParachainReporterSlashed(uint32 _paraId, address _reporter, address _recipient, uint256 _slashAmount);
    event ParachainStakeWithdrawRequested(uint32 _paraId, address _staker, uint256 _amount);
    event ParachainStakeWithdrawRequestConfirmed(uint32 _paraId, address _staker, uint256 _amount);
    event ParachainStakeWithdrawn(uint32 _paraId, address _staker);
    event ParachainValueRemoved(uint32 _paraId, bytes32 _queryId, uint256 _timestamp);

    constructor(
        address _parachain,
        address _token,
        uint256 _reportingLock,
        uint256 _stakeAmountDollarTarget,
        uint256 _stakingTokenPrice,
        uint256 _minimumStakeAmount,
        bytes32 _stakingTokenPriceQueryId

        ) Parachain(_parachain) 
        TellorFlex(
            _token,
            _reportingLock,
            _stakeAmountDollarTarget,
            _stakingTokenPrice,
            _minimumStakeAmount,
            _stakingTokenPriceQueryId
        ) {}


    function depositParachainStake(uint32 _paraId, bytes calldata _account, uint256 _amount) external {
        require(governance != address(0), "governance address not set");

        // Ensure parachain is registered
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "Parachain not registered");
        // Ensure called by parachain owner
        require(msg.sender == parachainOwner, "Must be parachain owner");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakeInfo[_paraId][msg.sender];
        _parachainStakeInfo._account = _account;

        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        uint256 _stakedBalance = _staker.stakedBalance;
        uint256 _lockedBalance = _staker.lockedBalance;
        if (_lockedBalance > 0) {
            if (_lockedBalance >= _amount) {
                // if staker's locked balance covers full _amount, use that
                _staker.lockedBalance -= _amount;
                toWithdraw -= _amount;
            } else {
                // otherwise, stake the whole locked balance and transfer the
                // remaining amount from the staker's address
                require(
                    token.transferFrom(
                        msg.sender,
                        address(this),
                        _amount - _lockedBalance
                    )
                );
                toWithdraw -= _staker.lockedBalance;
                _staker.lockedBalance = 0;
            }
        } else {
            if (_stakedBalance == 0) {
                // if staked balance and locked balance equal 0, save current vote tally.
                // voting participation used for calculating rewards
                (bool _success, bytes memory _returnData) = governance.call(
                    abi.encodeWithSignature("getVoteCount()")
                );
                if (_success) {
                    _staker.startVoteCount = uint256(abi.decode(_returnData, (uint256)));
                }
                (_success,_returnData) = governance.call(
                    abi.encodeWithSignature("getVoteTallyByAddress(address)",msg.sender)
                );
                if(_success){
                    _staker.startVoteTally =  abi.decode(_returnData,(uint256));
                }
            }
            require(token.transferFrom(msg.sender, address(this), _amount));
        }
        _updateStakeAndPayRewards(msg.sender, _stakedBalance + _amount);
        _staker.startDate = block.timestamp; // This resets the staker start date to now
        emit NewStaker(msg.sender, _amount);
        emit NewParachainStaker(_paraId, msg.sender, _account, _amount);

        reportStakeDeposited(_paraId, msg.sender, _account, _amount);
    }


    function requestParachainStakeWithdraw(uint32 _paraId, uint256 _amount, address _reporter) external {
        // Ensure parachain is registered
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "Parachain not registered");
        // Ensure called by parachain owner
        require(msg.sender == parachainOwner, "Must be parachain owner");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakeInfo[_paraId][_reporter]; 
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        require(
            _staker.stakedBalance >= _amount,
            "insufficient staked balance"
        );
        _updateStakeAndPayRewards(_reporter, _staker.stakedBalance - _amount);
        _staker.startDate = block.timestamp;
        _staker.lockedBalance += _amount;
        toWithdraw += _amount;
        emit StakeWithdrawRequested(_reporter, _amount);
        emit ParachainStakeWithdrawRequested(_paraId, _reporter, _amount);

        reportStakeWithdrawRequested(_paraId, msg.sender, _amount);
    }


    // Attacks are prevented bc caller must be the parachain owner
    // Still don't understand why this func is needed
    function confirmParachainStakeWithdrawRequest(uint32 _paraId, address _reporter, uint256 _amount) external {
        // spec says msg.owner, but that seems wrong?
        require(msg.sender == registry.owner(_paraId), "not parachain owner");

        // Not rly sure what else this func is supposed to do
        // Update ParachainStakeInfo._lockedBalanceConfirmed ?

        emit ParachainStakeWithdrawRequestConfirmed(_paraId, _reporter, _amount);
    }

    // Slash attacks prevented bc caller must be governance contract
    function slashParachainReporter(uint32 _paraId, address _reporter, address _recipient) external returns (uint256) {
        require(msg.sender == governance, "only governance can slash reporter");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakeInfo[_paraId][_reporter];
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        uint256 _slashAmount = _staker.stakedBalance;
        _updateStakeAndPayRewards(_reporter, 0);
        require(token.transfer(_recipient, _slashAmount), "transfer failed");
        emit ParachainReporterSlashed(_paraId, _reporter, _recipient, _slashAmount);

        reportSlash(_paraId, _reporter, _recipient, _slashAmount);
        return _slashAmount;
    }

    // Attacks on others' stakes prevented bc updates happen based on msg.sender
    function withdrawParachainStake(uint32 _paraId) external {
        ParachainStakeInfo storage _parachainStakeInfo = parachainStakeInfo[_paraId][msg.sender];
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        require(
            block.timestamp - _staker.startDate >= 7 days,
            "lock period not expired"
        );
        require(
            _staker.lockedBalance > 0,
            "no locked balance to withdraw"
        );
        uint256 _amount = _staker.lockedBalance;
        require(token.transfer(msg.sender, _amount), "withdraw stake token transfer failed");
        toWithdraw -= _amount;
        _staker.lockedBalance = 0;

        emit StakeWithdrawn(msg.sender);
        emit ParachainStakeWithdrawn(_paraId, msg.sender);

        reportStakeWithdrawn(_paraId, msg.sender, _amount);
    }

}