pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Tellor } from "./Tellor.sol";

contract Staking is Tellor  {
    address public owner;
    IERC20 public token;

    event DepositedStake(address caller, uint32 parachain);
    event DisputeStarted(address caller, uint32 parachain);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor (address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    error NotOwner();
    error InsufficientStakeAmount();

    // Register parachain, along with index of Tellor pallet within corresponding runtime and stake amount
    function register(uint32 _paraId, uint8 _palletIndex, uint256 _stakeAmount) external onlyOwner {
        // todo: fund parachain derivative account with msg.value
        Tellor.registerParachain(_paraId, _palletIndex, _stakeAmount);
    }

    // Deposit stake: called by reporter
    function depositStake(uint32 _paraId, uint256 _amount) external {

        if (Tellor.owner(_paraId) == address(0x0))
            revert ParachainNotRegistered();
        if (_amount < Tellor.stakeAmount(_paraId))
            revert InsufficientStakeAmount();

        // todo: Deposit state

        // Notify parachain
        Tellor.reportStake(_paraId, msg.sender, _amount);
        emit DepositedStake(msg.sender, _paraId);
    }

    function beginDispute(uint32 _paraId) external {
        if (Tellor.owner(_paraId) == address(0x0))
            revert ParachainNotRegistered();

        // todo: dispute

        emit DisputeStarted(msg.sender, _paraId);
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