pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Parachain } from "./Parachain.sol";
// import { IRegistry, ParachainRegistry, ParachainNotRegistered, NotOwner } from "./ParachainRegistry.sol";
import { IRegistry, ParachainRegistry } from "./ParachainRegistry.sol";


contract Governance is Parachain  {
    address public owner;

    event DisputeStarted(address caller, uint32 parachain);
    event ParachainValueRemoved(uint32 _paraId, bytes32 _queryId, uint256 _timestamp);
    event ParachainVoteExecuted(uint32 _paraId, uint256 _disputeId);
    event ParachainVoteTallied(uint32 _paraId, uint256 _disputeId);
    event ParachainVoted(uint32 _paraId, uint256 _disputeId, bytes _vote);

    modifier onlyOwner {
        // if (msg.sender != owner) revert NotOwner();
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor (address _registry) Parachain(_registry) {
        owner = msg.sender;
    }

    function beginParachainDispute(uint32 _paraId) external {
        // Ensure that sender is parachain owner
        address parachainOwner = registry.owner(_paraId);
        // if (parachainOwner == address(0x0)) revert ParachainNotRegistered();
        require(parachainOwner != address(0x0), "Parachain not registered");
        // if (msg.sender != parachainOwner) revert NotOwner();
        require(msg.sender == parachainOwner, "Not owner");

        // todo: dispute

        emit DisputeStarted(msg.sender, _paraId);
    }

    // Remove value: called as part of dispute resolution
    // note: call must originate from the Governance contract due to access control within the pallet.
    function removeParachainValue(uint32 _paraId, bytes32 _queryId, uint256 _timestamp) external onlyOwner { // temporarily external for testing: must ultimately be *private*

        // if (registry.owner(_paraId) == address(0x0)) 
            // revert ParachainNotRegistered();
        require(registry.owner(_paraId) != address(0x0), "Parachain not registered");

        // Notify parachain
        removeValue(_paraId, _queryId, _timestamp);
        emit ParachainValueRemoved(_paraId, _queryId, _timestamp);
    }

    function executeParachainVote(uint32 _paraId, uint256 _disputeId) external onlyOwner {
        require(registry.owner(_paraId) != address(0x0), "Parachain not registered");

        // todo: execute vote
        emit ParachainVoteExecuted(_paraId, _disputeId);
    }

    function tallyParachainVotes(uint32 _paraId, uint256 _disputeId) external onlyOwner {
        require(registry.owner(_paraId) != address(0x0), "Parachain not registered");

        // todo: tally votes
        emit ParachainVoteTallied(_paraId, _disputeId);
    }

    function voteParachain(uint32 _paraId, uint256 _disputeId, bytes calldata vote) external {
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "Parachain not registered");
        require(msg.sender == parachainOwner, "Not owner");

        // todo: vote
        emit ParachainVoted(_paraId, _disputeId, vote);
    }
}