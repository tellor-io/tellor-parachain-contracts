pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Parachain } from "./Parachain.sol";
// import { IRegistry, ParachainRegistry, ParachainNotRegistered, NotOwner } from "./ParachainRegistry.sol";
import { IRegistry, ParachainRegistry } from "./ParachainRegistry.sol";
import { Governance } from "lib/tellor/Governance.sol";


contract ParachainGovernance is Parachain, Governance  {
    address public owner;

    mapping(uint32 => mapping(bytes32 => uint256[])) private parachainVoteRounds;
    mapping(uint32 => mapping(uint256 => Vote)) private parachainVoteInfo;
    mapping(uint32 => mapping(uint256 => Dispute)) private parachainDisputeInfo;

    event DisputeStarted(address caller, uint32 parachain);
    event ParachainValueRemoved(uint32 _paraId, bytes32 _queryId, uint256 _timestamp);
    event ParachainVoteExecuted(uint32 _paraId, uint256 _disputeId);
    event ParachainVoteTallied(uint32 _paraId, uint256 _disputeId);
    event ParachainVoted(uint32 _paraId, uint256 _disputeId, bytes _vote);

    modifier onlyOwner {
        // if (msg.sender != owner) revert NotOwner();
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor (
        address _registry,
        address payable _tellor,
        address _teamMultiSig
        ) 
    Parachain(_registry) 
    Governance(_tellor, _teamMultiSig)
    {
        owner = msg.sender;
    }


    /// @dev Start dispute/vote for a specific parachain
    /// @param _paraId uint32 Parachain ID, where the dispute was initiated
    /// @param _queryId bytes32 Query ID being disputed
    /// @param _timestamp uint256 Timestamp being disputed
    /// @param _disputeId uint256 Dispute ID on the parachain
    /// @param _value bytes Value disputed
    /// @param _disputedReporter address Reporter who submitted the disputed value
    /// @param _disputeInitiator address Initiator who started the dispute/proposal
    function beginParachainDispute(uint32 _paraId, bytes32 _queryId, uint256 _timestamp, uint256 _disputeId, bytes calldata _value, address _disputedReporter, address _disputeInitiator) external {
        // Ensure parachain is registered & sender is parachain owner
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");
        require(msg.sender == parachainOwner, "not owner");

        // Trusts that the corresponding value for the supplied query identifier and timestamp 
        // exists on the consumer parachain, that it has been removed during dispute initiation, 
        // and that a dispute fee has been locked.

        bytes32 _hash = keccak256(abi.encodePacked(_queryId, _timestamp));
        // Push new vote round
        uint256[] storage _voteRounds = parachainVoteRounds[_paraId][_hash];
        _voteRounds.push(_disputeId);

        // Create new vote and dispute
        Vote storage _thisVote = parachainVoteInfo[_paraId][_disputeId];
        Dispute storage _thisDispute = parachainDisputeInfo[_paraId][_disputeId];

        // Set dispute information
        _thisDispute.queryId = _queryId;
        _thisDispute.timestamp = _timestamp;
        _thisDispute.disputedReporter = _disputedReporter;
        // Set vote information
        _thisVote.identifierHash = _hash;
        _thisVote.initiator = _disputeInitiator;
        _thisVote.blockNumber = block.number;
        _thisVote.startDate = block.timestamp;
        _thisVote.voteRound = _voteRounds.length;

        // todo: update dispute ids by reporter, & change the rest of the original func

        emit DisputeStarted(msg.sender, _paraId);
    }

    // Remove value: called as part of dispute resolution
    // note: call must originate from the Governance contract due to access control within the pallet.
    function removeParachainValue(uint32 _paraId, bytes32 _queryId, uint256 _timestamp) external onlyOwner { // temporarily external for testing: must ultimately be *private*

        // if (registry.owner(_paraId) == address(0x0)) 
            // revert ParachainNotRegistered();
        require(registry.owner(_paraId) != address(0x0), "parachain not registered");

        // Notify parachain
        removeValue(_paraId, _queryId, _timestamp);
        emit ParachainValueRemoved(_paraId, _queryId, _timestamp);
    }

    function executeParachainVote(uint32 _paraId, uint256 _disputeId) external onlyOwner {
        require(registry.owner(_paraId) != address(0x0), "parachain not registered");

        // todo: execute vote
        emit ParachainVoteExecuted(_paraId, _disputeId);
    }

    function tallyParachainVotes(uint32 _paraId, uint256 _disputeId) external onlyOwner {
        require(registry.owner(_paraId) != address(0x0), "parachain not registered");

        // todo: tally votes
        emit ParachainVoteTallied(_paraId, _disputeId);
    }

    function voteParachain(uint32 _paraId, uint256 _disputeId, bytes calldata vote) external {
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");
        require(msg.sender == parachainOwner, "not owner");

        // todo: vote
        emit ParachainVoted(_paraId, _disputeId, vote);
    }
}