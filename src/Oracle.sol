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
        uint256 _lockedBalanceConfirmed;
    }

    // Parachain stake info is sorted by parachain ID, then the parachain account bytes.
    mapping(uint32 => mapping(address => ParachainStakeInfo)) private parachainStakeInfo;

    event NewParachainStaker(uint32 _paraId, address _staker, bytes _account, uint256 _amount);
    event ParachainReporterSlashed(uint32 _paraId, address _reporter, address _recipient, uint256 _slashAmount);
    event ParachainStakeWithdrawRequested(uint32 _paraId, bytes _account, uint256 _amount);
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


    /// @dev Called by the staker on the EVM compatible parachain that hosts the Tellor controller contracts.
    /// The staker will call this function and pass in the parachain account identifier, which is used to enable
    /// that account to report values over on the oracle consumer parachain.
    function depositParachainStake(uint32 _paraId, bytes calldata _account, uint256 _amount) external {
        require(governance != address(0), "governance address not set");

        // Ensure parachain is registered
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");

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

    /// @dev Allows a staker on EVM compatible parachain to request withdrawal of their stake for 
    /// a specific oracle consumer parachain.
    function requestParachainStakeWithdraw(uint32 _paraId, uint256 _amount) external {
        // Ensure parachain is registered
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakeInfo[_paraId][msg.sender]; 
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        require(
            _staker.stakedBalance >= _amount,
            "insufficient staked balance"
        );
        _updateStakeAndPayRewards(msg.sender, _staker.stakedBalance - _amount);
        _staker.startDate = block.timestamp;
        _staker.lockedBalance += _amount;
        toWithdraw += _amount;
        emit StakeWithdrawRequested(msg.sender, _amount);
        emit ParachainStakeWithdrawRequested(_paraId, _parachainStakeInfo._account, _amount);

        reportStakeWithdrawRequested(_paraId, _parachainStakeInfo._account, _amount);
    }


    function confirmParachainStakeWithdrawRequest(uint32 _paraId, address _staker, uint256 _amount) external {
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");
        require(msg.sender == registry.owner(_paraId), "not parachain owner");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakeInfo[_paraId][_staker];
        _parachainStakeInfo._lockedBalanceConfirmed = _amount;

        emit ParachainStakeWithdrawRequestConfirmed(_paraId, _staker, _amount);
    }


    function slashParachainReporter(uint32 _paraId, address _reporter, address _recipient) external returns (uint256) {
        require(msg.sender == governance, "only governance can slash reporter");
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakeInfo[_paraId][_reporter];
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        uint256 _slashAmount = _staker.stakedBalance;
        _updateStakeAndPayRewards(_reporter, 0);
        require(token.transfer(_recipient, _slashAmount), "transfer failed");
        emit ParachainReporterSlashed(_paraId, _reporter, _recipient, _slashAmount);

        reportSlash(_paraId, _reporter, _recipient, _slashAmount);
        return _slashAmount;
    }


    /// @dev Allows a staker to withdraw their stake for a specific parachain.
    function withdrawParachainStake(uint32 _paraId) external {
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");

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
        require(
            _staker.lockedBalance == _parachainStakeInfo._lockedBalanceConfirmed,
            "withdraw stake request not confirmed"
        );
        uint256 _amount = _staker.lockedBalance;
        require(token.transfer(msg.sender, _amount), "withdraw stake token transfer failed");
        toWithdraw -= _amount;
        _staker.lockedBalance = 0;
        _parachainStakeInfo._lockedBalanceConfirmed = 0;

        emit StakeWithdrawn(msg.sender);
        emit ParachainStakeWithdrawn(_paraId, msg.sender);

        reportStakeWithdrawn(_paraId, msg.sender, _parachainStakeInfo._account, _amount);
    }

}