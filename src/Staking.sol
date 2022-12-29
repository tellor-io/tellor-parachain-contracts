pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { InsufficientStakeAmount, ITellor, ParachainNotRegistered } from "./Tellor.sol";

contract Staking  {
    address private owner;
    IERC20 private token;
    ITellor private tellor;

    event DepositedStake(address caller, uint32 parachain);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor (address _token, address _tellor) {
        owner = msg.sender;
        token = IERC20(_token);
        tellor = ITellor(_tellor);
    }

    error NotOwner();

    // Deposit stake: called by reporter
    function depositStake(uint32 _paraId, uint256 _amount) external {

        if (tellor.owner(_paraId) == address(0x0))
            revert ParachainNotRegistered();
        if (_amount < tellor.stakeAmount(_paraId))
            revert InsufficientStakeAmount();

        // todo: Deposit state

        // Notify parachain
        tellor.reportStake(_paraId, msg.sender, _amount);
        emit DepositedStake(msg.sender, _paraId);
    }

//    function requestStakingWithdraw(uint256 _amount) external {
//    }
//
//    function withdrawStake() external {
//    }
//
//    function slashReporter(address _reporter, address _recipient) external {
//
//    }

}