pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Parachain } from "./Parachain.sol";
import { IRegistry, ParachainRegistry, ParachainNotRegistered } from "./ParachainRegistry.sol";

    error InsufficientStakeAmount();

contract Staking is Parachain {
    address private owner;
    IERC20 private token;

    event NewParachainStaker(address caller, uint32 parachain);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor (address _token, address _registry) Parachain(_registry) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    error NotOwner();

    // Deposit stake: called by staker/reporter, where _account is the reporters account identifier on the corresponding parachain
    function depositParachainStake(uint32 _paraId, bytes calldata _account, uint256 _amount) external {

        if (registry.owner(_paraId) == address(0x0))
            revert ParachainNotRegistered();
        if (_amount < registry.stakeAmount(_paraId))
            revert InsufficientStakeAmount();

        // todo: Deposit state

        // Notify parachain
        reportStake(_paraId, msg.sender, _account, _amount);
        emit NewParachainStaker(msg.sender, _paraId);
    }
}
