pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Parachain } from "./Parachain.sol";
// import { IRegistry, ParachainRegistry, ParachainNotRegistered, NotOwner } from "./ParachainRegistry.sol";
import { IRegistry, ParachainRegistry } from "./ParachainRegistry.sol";
import { Governance } from "lib/tellor/Governance.sol";
import { IParachainStaking } from "./ParachainStaking.sol";


contract ParachainGovernance is Parachain, Governance  {
    address public owner;

    IParachainStaking public parachainStaking;

    mapping(uint32 => mapping(bytes32 => uint256[])) private parachainVoteRounds;
    mapping(uint32 => mapping(uint256 => Vote)) private parachainVoteInfo;
    mapping(uint32 => mapping(uint256 => Dispute)) private parachainDisputeInfo;
    mapping(uint32 => mapping(address => uint256[])) private disputeIdsByParachainReporter;
    mapping(uint32 => mapping(bytes32 => uint256)) private openDisputesOnIdByParachain;
    mapping(uint32 => uint256) private parachainVoteCount;

    event NewParachainDispute(uint32 _paraId, uint256 _disputeId, bytes32 _queryId, uint256 _timestamp, address _reporter);
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


    // / @dev Start dispute/vote for a specific parachain
    // / @param _paraId uint32 Parachain ID, where the dispute was initiated
    // / @param _queryId bytes32 Query ID being disputed
    // / @param _timestamp uint256 Timestamp being disputed
    // / @param _disputeId uint256 Dispute ID on the parachain
    // / @param _value bytes Value disputed
    // / @param _disputedReporter address Reporter who submitted the disputed value
    // / @param _disputeInitiator address Initiator who started the dispute/proposal
    // function beginParachainDispute(uint32 _paraId, bytes32 _queryId, uint256 _timestamp, uint256 _disputeId, bytes calldata _value, address _disputedReporter, address _disputeInitiator) external {
    //     // Ensure parachain is registered & sender is parachain owner
    //     address parachainOwner = registry.owner(_paraId);
    //     require(parachainOwner != address(0x0), "parachain not registered");
    //     require(msg.sender == parachainOwner, "not owner");

    //     // Trusts that the corresponding value for the supplied query identifier and timestamp 
    //     // exists on the consumer parachain, that it has been removed during dispute initiation, 
    //     // and that a dispute fee has been locked.

    //     // ^From spec. Shouldn't the dispute fee amount be passed in as an argument?
    //     // Not sure where tokens should be locked.. 

    //     bytes32 _hash = keccak256(abi.encodePacked(_paraId, _queryId, _timestamp));
    //     // Push new vote round
    //     uint256[] storage _voteRounds = voteRounds[_hash];
    //     _voteRounds.push(_disputeId);

    //     // Create new vote and dispute
    //     Vote storage _thisVote = voteInfo[_disputeId];
    //     Dispute storage _thisDispute = disputeInfo[_disputeId];

    //     // Set dispute information
    //     _thisDispute.queryId = _queryId;
    //     _thisDispute.timestamp = _timestamp;
    //     _thisDispute.disputedReporter = _disputedReporter;
    //     // Set vote information
    //     _thisVote.identifierHash = _hash;
    //     _thisVote.initiator = _disputeInitiator;
    //     _thisVote.blockNumber = block.number; 
    //     _thisVote.startDate = block.timestamp; // This is correct bc consumer parachain must submit votes before voting period ends
    //     _thisVote.voteRound = _voteRounds.length;
    //     // disputeIdsByReporter must organize by parachain, then reporter, since
    //     // there could be duplicate dispute ids from one staker enabling multiple reporters on
    //     // different parachains.
    //     disputeIdsByParachainReporter[_paraId][_disputedReporter].push(_disputeId);

    //     uint256 _disputeFee = getDisputeFee();
    //     if (_voteRounds.length == 1) { // Assumes _voteRounds will never be empty
    //         require(
    //             block.timestamp - _timestamp < 12 hours,
    //             "Dispute must be started within reporting lock time"
    //         );
    //         openDisputesOnIdByParachain[_paraId][_queryId]++;
    //         // calculate dispute fee based on number of open disputes on query ID
    //         _disputeFee = _disputeFee * 2**(openDisputesOnIdByParachain[_paraId][_queryId] - 1);
    //         // slash a single stakeAmount from reporter
    //         // Following command throws error:
    //         // TypeError: Type tuple() is not implicitly convertible to expected type uint256.
    //         // Once commneted out, the above command throws a "Stack too deep" error.
    //         _thisDispute.slashedAmount = parachainStaking.slashParachainReporter(
    //             _paraId,
    //             _thisDispute.disputedReporter,
    //             address(this)
    //         );
    //         _thisDispute.value = _value;
    //         // Idk why spec says we're assuming the value was already removed? Removing here:
    //         removeParachainValue(_paraId, _queryId, _timestamp);
    //     } else {
    //         uint256 _prevId = _voteRounds[_voteRounds.length - 2];
    //         require(
    //             block.timestamp - parachainVoteInfo[_paraId][_prevId].tallyDate < 1 days,
    //             "New dispute round must be started within a day"
    //         );
    //         _disputeFee = _disputeFee * 2**(_voteRounds.length - 1);
    //         _thisDispute.slashedAmount = parachainDisputeInfo[_paraId][_voteRounds[0]].slashedAmount;
    //         _thisDispute.value = parachainDisputeInfo[_paraId][_voteRounds[0]].value;
    //     }
    //     _thisVote.fee = _disputeFee;
    //     parachainVoteCount[_paraId]++;
    //     require(
    //         // Should the transfer be from the consumer parachain pallet?
    //         // Or should this be changed to the _disputeInitiator?
    //         token.transferFrom(msg.sender, address(this), _disputeFee),
    //         "Fee must be paid"
    //     ); // This is the dispute fee. Returned if dispute passes
    //     emit NewParachainDispute(
    //         _paraId,
    //         _disputeId,
    //         _queryId,
    //         _timestamp,
    //         _disputedReporter
    //     );
    // }

    // Remove value: called as part of dispute resolution
    // note: call must originate from the Governance contract due to access control within the pallet.
    function removeParachainValue(uint32 _paraId, bytes32 _queryId, uint256 _timestamp) private onlyOwner { // temporarily external for testing: must ultimately be *private*

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