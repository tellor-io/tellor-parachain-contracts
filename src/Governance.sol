pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Parachain } from "./Parachain.sol";
import { IRegistry, ParachainRegistry, ParachainNotRegistered, NotOwner } from "./ParachainRegistry.sol";

contract Governance is Parachain  {
    address public owner;

    event DisputeStarted(address caller, uint32 parachain);
    event ParachainValueRemoved(uint32 _paraId, bytes32 _queryId, uint256 _timestamp);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor (address _registry) Parachain(_registry) {
        owner = msg.sender;
    }

    function beginParachainDispute(uint32 _paraId) external {
        // Ensure that sender is parachain owner
        address parachainOwner = registry.owner(_paraId);
        if (parachainOwner == address(0x0)) revert ParachainNotRegistered();
        if (msg.sender != parachainOwner) revert NotOwner();

        // todo: dispute

        emit DisputeStarted(msg.sender, _paraId);
    }

    // Remove value: called as part of dispute resolution
    // note: call must originate from the Governance contract due to access control within the pallet.
    function removeParachainValue(uint32 _paraId, bytes32 _queryId, uint256 _timestamp) external onlyOwner { // temporarily external for testing: must ultimately be *private*

        if (registry.owner(_paraId) == address(0x0))
            revert ParachainNotRegistered();

        // Notify parachain
        removeValue(_paraId, _queryId, _timestamp);
        emit ParachainValueRemoved(_paraId, _queryId, _timestamp);
    }
}