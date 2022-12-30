pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { ITellor, NotOwner, ParachainNotRegistered } from "./Tellor.sol";

contract Governance  {
    address public owner;
    ITellor private tellor;

    event DisputeStarted(address caller, uint32 parachain);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor (address _tellor) {
        owner = msg.sender;
        tellor = ITellor(_tellor);
    }

    function beginDispute(uint32 _paraId) external {
        // Ensure that sender is parachain owner
        address parachainOwner = tellor.owner(_paraId);
        if (parachainOwner == address(0x0)) revert ParachainNotRegistered();
        if (msg.sender != parachainOwner) revert NotOwner();

        // todo: dispute

        emit DisputeStarted(msg.sender, _paraId);
    }
}