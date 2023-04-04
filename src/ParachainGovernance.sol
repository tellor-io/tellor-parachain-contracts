pragma solidity ^0.8.3;

import "../lib/moonbeam/precompiles/ERC20.sol";
import {Parachain} from "./Parachain.sol";
// import { IRegistry, ParachainRegistry, ParachainNotRegistered, NotOwner } from "./ParachainRegistry.sol";
import {IRegistry, ParachainRegistry} from "./ParachainRegistry.sol";
import {IParachainStaking} from "./ParachainStaking.sol";
import {IParachainGovernance} from "./interfaces/IParachainGovernance.sol";

/**
 * @author Tellor Inc.
 *  @title Parachain Governance
 *  @dev This is a governance contract to be used with ParachainStaking. It resolves disputes
 * and votes sent from oracle consumer chains.
 */
contract ParachainGovernance is Parachain {
    // Storage
    address public owner;
    IParachainStaking public parachainStaking;
    IERC20 public token; // token used for staking
    address public teamMultisig; // address of team multisig wallet, one of four stakeholder groups
    bytes32 public autopayAddrsQueryId = keccak256(abi.encode("AutopayAddresses", abi.encode(bytes("")))); // query id for autopay addresses array
    mapping(bytes32 => Dispute) private disputeInfo; // mapping of dispute IDs to the details of the dispute
    mapping(bytes32 => mapping(uint8 => Vote)) private voteInfo; // mapping of dispute IDs to vote round number to vote details
    mapping(bytes32 => uint8) private voteRounds; // mapping of dispute IDs to the number of vote rounds
    mapping(address => uint256) private voteTallyByAddress; // mapping of addresses to the number of votes they have cast
    mapping(address => bytes32[]) private disputeIdsByReporter; // mapping of reporter addresses to an array of dispute IDs

    enum VoteResult {
        FAILED,
        PASSED,
        INVALID
    } // status of a potential vote

    // Structs
    struct Dispute {
        uint32 paraId; // parachain ID of the dispute
        bytes32 queryId; // query ID of disputed value
        uint256 timestamp; // timestamp of disputed value
        bytes value; // disputed value
        address disputedReporter; // reporter who submitted the disputed value
        uint256 slashedAmount; // amount of tokens slashed from reporter
    }

    struct Tally {
        uint256 doesSupport; // number of votes in favor
        uint256 against; // number of votes against
        uint256 invalidQuery; // number of votes for invalid
    }

    struct Vote {
        bytes32 identifierHash; // identifier hash of the vote
        uint256 voteRound; // the round of voting on a given dispute or proposal
        uint256 startDate; // timestamp of when vote was initiated
        uint256 blockNumber; // block number of when vote was initiated
        uint256 tallyDate; // timestamp of when the votes were tallied
        Tally tokenholders; // vote tally of tokenholders
        Tally users; // vote tally of users
        Tally reporters; // vote tally of reporters
        Tally teamMultisig; // vote tally of teamMultisig
        bool executed; // boolean of whether the vote was executed
        VoteResult result; // VoteResult after votes were tallied
        address initiator; // address which initiated dispute/proposal
        mapping(address => bool) voted; // mapping of address to whether or not they voted
    }

    // Events
    event NewParachainDispute(uint32 _paraId, bytes32 _queryId, uint256 _timestamp, address _reporter);
    event VoteExecuted(bytes32 _disputeId, VoteResult _result);
    event VoteTallied(bytes32 _disputeId, VoteResult _result, address _initiator, address _reporter); // Emitted when all casting for a vote is tallied
    // event ParachainVoted(bytes32, uint256[] _vote);
    event ParachainVoted(
        bytes32 _disputId,
        uint256 _totalTipsFor,
        uint256 _totalTipsAgainst,
        uint256 _totalTipsInvalid,
        uint256 _totalReportsFor,
        uint256 _totalReportsAgainst,
        uint256 _totalReportsInvalid
    );
    event Voted(
        uint32 _paraId, bytes32 _queryId, uint256 _timestamp, bool _supports, address _voter, bool _invalidQuery
    ); // Emitted when an individual staker or the multisig casts their vote

    /**
     * @dev Initializes contract parameters
     * @param _registry address of ParachainRegistry contract
     * @param _teamMultiSig address of tellor team multisig, one of four voting
     * stakeholder groups
     */
    constructor(address _registry, address _teamMultiSig) Parachain(_registry) {
        teamMultisig = _teamMultiSig;
        owner = msg.sender;
    }

    /**
     * @dev Allows the owner to initialize the ParachainStaking and token interfaces
     * @param _parachainStaking address of ParachainStaking contract
     */
    // todo: does it need to be "address payable"?
    function init(address _parachainStaking) external {
        require(msg.sender == owner, "not owner");
        require(address(parachainStaking) == address(0), "parachainStaking address already set");
        require(_parachainStaking != address(0), "parachainStaking address can't be zero address");
        parachainStaking = IParachainStaking(_parachainStaking);
        token = IERC20(parachainStaking.getTokenAddress());
    }

    /**
     * @dev Start dispute/vote for a specific parachain
     * // Trusts that the corresponding value for the supplied query identifier and timestamp
     * // exists on the consumer parachain, that it has been removed during dispute initiation,
     * // and that a dispute fee has been locked.
     * @param _queryId bytes32 Query ID of disputed value
     * @param _timestamp uint256 Timestamp of disputed value
     * @param _value bytes Value disputed
     * @param _disputedReporter address Reporter who submitted the disputed value
     * @param _disputeInitiator address Initiator who started the dispute/proposal
     * @param _slashAmount uint256 Amount of tokens to be slashed of staker
     */
    function beginParachainDispute(
        bytes32 _queryId,
        uint256 _timestamp,
        bytes calldata _value,
        address _disputedReporter,
        address _disputeInitiator,
        uint256 _slashAmount
    ) external {
        // Ensure parachain is registered & sender is parachain owner
        IRegistry.Parachain memory parachain = registry.getByAddress(msg.sender);
        require(parachain.owner == msg.sender && parachain.owner != address(0x0), "not owner");

        // Create unique identifier for this dispute
        bytes32 _disputeId = keccak256(abi.encode(parachain.id, _queryId, _timestamp));

        // Check if able to start new voting round
        if (voteRounds[_disputeId] >= 1) {
            // This condition also ensures that previous round is tallied, because block.timestamp - 0 != 1 day.
            // This condition also ensures that previous round is not executed, because if it was, 1 day or more would have passed.
            require(
                block.timestamp - voteInfo[_disputeId][voteRounds[_disputeId]].tallyDate < 1 days,
                "New dispute round must be started within a day"
            );
        }
        voteRounds[_disputeId]++;

        // Set vote info
        Vote storage _thisVote = voteInfo[_disputeId][voteRounds[_disputeId]];
        _thisVote.identifierHash = _disputeId;
        _thisVote.initiator = _disputeInitiator;
        _thisVote.blockNumber = block.number;
        _thisVote.startDate = block.timestamp; // This is correct bc consumer parachain must submit votes before voting period ends
        _thisVote.voteRound = voteRounds[_disputeId];

        if (voteRounds[_disputeId] == 1) {
            // First round of voting
            require(block.timestamp - _timestamp < 12 hours, "Dispute must be started within reporting lock time");

            // Set dispute information
            Dispute storage _thisDispute = disputeInfo[_disputeId];
            _thisDispute.value = _value;
            _thisDispute.paraId = parachain.id;
            _thisDispute.queryId = _queryId;
            _thisDispute.timestamp = _timestamp;
            _thisDispute.disputedReporter = _disputedReporter;
            _thisDispute.slashedAmount = disputeInfo[_disputeId].slashedAmount;

            disputeIdsByReporter[_disputedReporter].push(_disputeId);

            // slash a single stakeAmount from reporter
            _thisDispute.slashedAmount = parachainStaking.slashParachainReporter(
                _slashAmount, parachain.id, _thisDispute.disputedReporter, address(this)
            );
        }

        emit NewParachainDispute(parachain.id, _queryId, _timestamp, _disputedReporter);
    }

    /**
     * @dev Enables the sender address (staker or multisig) to cast a vote
     * @param _disputeId is the unique identifier for the dispute
     * @param _supports is the address's vote: whether or not they support or are against
     * @param _validDispute is whether or not the dispute is valid (e.g. false if the dispute is invalid)
     */
    function vote(bytes32 _disputeId, bool _supports, bool _validDispute) external {
        Vote storage _thisVote = voteInfo[_disputeId][voteRounds[_disputeId]];

        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate == 0, "Vote has already been tallied");
        require(!_thisVote.voted[msg.sender], "Sender has already voted");

        Dispute storage _thisDispute = disputeInfo[_disputeId];

        // Update voting status and increment total queries for support, invalid, or against based on vote
        _thisVote.voted[msg.sender] = true;
        uint256 _tokenBalance = token.balanceOf(msg.sender);
        (, uint256 _stakedBalance, uint256 _lockedBalance,,,,,,) =
            parachainStaking.getParachainStakerInfo(_thisDispute.paraId, msg.sender);
        _tokenBalance += _stakedBalance + _lockedBalance;

        if (!_validDispute) {
            // If vote is invalid
            _thisVote.tokenholders.invalidQuery += _tokenBalance;
            if (msg.sender == teamMultisig) {
                _thisVote.teamMultisig.invalidQuery += 1;
            }
        } else if (_supports) {
            _thisVote.tokenholders.doesSupport += _tokenBalance;
            if (msg.sender == teamMultisig) {
                _thisVote.teamMultisig.doesSupport += 1;
            }
        } else {
            _thisVote.tokenholders.against += _tokenBalance;
            if (msg.sender == teamMultisig) {
                _thisVote.teamMultisig.against += 1;
            }
        }
        voteTallyByAddress[msg.sender]++;
        emit Voted(
            _thisDispute.paraId, _thisDispute.queryId, _thisDispute.timestamp, _supports, msg.sender, _validDispute
            );
    }

    /**
     * @dev Enables oracle consumer parachain to cast collated votes of its users and reporters for an open dispute.
     *      This function is called by the oracle consumer parachain, and can be called multiple times.
     * @param _disputeId is the ID of the dispute
     * @param _totalTipsFor is the total amount of tips contributed by users who voted for the dispute
     * @param _totalTipsAgainst is the total amount of tips contributed by users who voted against the dispute
     * @param _totalTipsInvalid is the total amount of tips contributed by users who voted invalid for the dispute
     * @param _totalReportsFor is the total number of reports submitted by reporters who voted for the dispute
     * @param _totalReportsAgainst is the total number of reports submitted by reporters who voted against the dispute
     * @param _totalReportsInvalid is the total number of reports submitted by reporters who voted invalid for the dispute
     */
    function voteParachain(
        bytes32 _disputeId,
        uint256 _totalTipsFor,
        uint256 _totalTipsAgainst,
        uint256 _totalTipsInvalid,
        uint256 _totalReportsFor,
        uint256 _totalReportsAgainst,
        uint256 _totalReportsInvalid
    ) external {
        // Ensure parachain is registered & sender is parachain owner
        IRegistry.Parachain memory parachain = registry.getByAddress(msg.sender);
        require(parachain.owner == msg.sender && parachain.owner != address(0x0), "not owner");

        require(parachain.id == disputeInfo[_disputeId].paraId, "invalid dispute identifier");

        Vote storage _thisVote = voteInfo[_disputeId][voteRounds[_disputeId]];
        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate == 0, "Vote has already been tallied");

        // Update users vote
        _thisVote.users.doesSupport = _totalTipsFor;
        _thisVote.users.against = _totalTipsAgainst;
        _thisVote.users.invalidQuery = _totalTipsInvalid;

        // Update reporters vote
        _thisVote.reporters.doesSupport = _totalReportsFor;
        _thisVote.reporters.against = _totalReportsAgainst;
        _thisVote.reporters.invalidQuery = _totalReportsInvalid;

        emit ParachainVoted(
            _disputeId,
            _totalTipsFor,
            _totalTipsAgainst,
            _totalTipsInvalid,
            _totalReportsFor,
            _totalReportsAgainst,
            _totalReportsInvalid
            );
    }

    /**
     * @dev Tallies the votes and begins the 1 day challenge period
     * @param _disputeId is the ID of the vote being tallied
     */
    function tallyVotes(bytes32 _disputeId) external {
        Vote storage _thisVote = voteInfo[_disputeId][voteRounds[_disputeId]];

        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate == 0, "Vote has already been tallied");

        // Determine appropriate vote duration dispute round
        // Vote time increases as rounds increase but only up to 6 days (withdrawal period)
        require(
            block.timestamp - _thisVote.startDate >= 1 days * _thisVote.voteRound
                || block.timestamp - _thisVote.startDate >= 6 days,
            "Time for voting has not elapsed"
        );
        // Get total votes from each separate stakeholder group.  This will allow
        // normalization so each group's votes can be combined and compared to
        // determine the vote outcome.
        uint256 _tokenVoteSum =
            _thisVote.tokenholders.doesSupport + _thisVote.tokenholders.against + _thisVote.tokenholders.invalidQuery;
        uint256 _reportersVoteSum =
            _thisVote.reporters.doesSupport + _thisVote.reporters.against + _thisVote.reporters.invalidQuery;
        uint256 _multisigVoteSum =
            _thisVote.teamMultisig.doesSupport + _thisVote.teamMultisig.against + _thisVote.teamMultisig.invalidQuery;
        uint256 _usersVoteSum = _thisVote.users.doesSupport + _thisVote.users.against + _thisVote.users.invalidQuery;
        // Cannot divide by zero
        if (_tokenVoteSum == 0) {
            _tokenVoteSum++;
        }
        if (_reportersVoteSum == 0) {
            _reportersVoteSum++;
        }
        if (_multisigVoteSum == 0) {
            _multisigVoteSum++;
        }
        if (_usersVoteSum == 0) {
            _usersVoteSum++;
        }
        // Normalize and combine each stakeholder group votes
        uint256 _scaledDoesSupport = ((_thisVote.tokenholders.doesSupport * 1e18) / _tokenVoteSum)
            + ((_thisVote.reporters.doesSupport * 1e18) / _reportersVoteSum)
            + ((_thisVote.teamMultisig.doesSupport * 1e18) / _multisigVoteSum)
            + ((_thisVote.users.doesSupport * 1e18) / _usersVoteSum);
        uint256 _scaledAgainst = ((_thisVote.tokenholders.against * 1e18) / _tokenVoteSum)
            + ((_thisVote.reporters.against * 1e18) / _reportersVoteSum)
            + ((_thisVote.teamMultisig.against * 1e18) / _multisigVoteSum)
            + ((_thisVote.users.against * 1e18) / _usersVoteSum);
        uint256 _scaledInvalid = ((_thisVote.tokenholders.invalidQuery * 1e18) / _tokenVoteSum)
            + ((_thisVote.reporters.invalidQuery * 1e18) / _reportersVoteSum)
            + ((_thisVote.teamMultisig.invalidQuery * 1e18) / _multisigVoteSum)
            + ((_thisVote.users.invalidQuery * 1e18) / _usersVoteSum);

        // If votes in support outweight the sum of against and invalid, result is passed
        if (_scaledDoesSupport > _scaledAgainst + _scaledInvalid) {
            _thisVote.result = VoteResult.PASSED;
            // If votes in against outweight the sum of support and invalid, result is failed
        } else if (_scaledAgainst > _scaledDoesSupport + _scaledInvalid) {
            _thisVote.result = VoteResult.FAILED;
            // Otherwise, result is invalid
        } else {
            _thisVote.result = VoteResult.INVALID;
        }

        _thisVote.tallyDate = block.timestamp; // Update time vote was tallied
        emit VoteTallied(_disputeId, _thisVote.result, _thisVote.initiator, disputeInfo[_disputeId].disputedReporter);
    }

    /**
     * @dev Executes vote and transfers corresponding balances to initiator/reporter
     * @param _disputeId is the ID of the vote being executed
     */
    function executeVote(bytes32 _disputeId) external {
        Vote storage _thisVote = voteInfo[_disputeId][voteRounds[_disputeId]];

        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate > 0, "Vote must be tallied");
        require(!_thisVote.executed, "Vote has already been executed");
        // Ensure vote must be final vote and that time has to be pass (86400 = 24 * 60 * 60 for seconds in a day)
        // todo: what exactly is this comment saying? ^
        require(voteRounds[_thisVote.identifierHash] == _thisVote.voteRound, "Must be the final vote");
        //The time  has to pass after the vote is tallied
        require(block.timestamp - _thisVote.tallyDate >= 1 days, "1 day has to pass after tally to allow for disputes");
        _thisVote.executed = true;
        Dispute storage _thisDispute = disputeInfo[_disputeId];
        if (_thisVote.result == VoteResult.PASSED) {
            // If vote is in dispute and passed, iterate through each vote round and transfer reporter's slashed stake to initiator
            token.transfer(_thisVote.initiator, _thisDispute.slashedAmount); // todo: should be wrapped in require statement?
        } else {
            // If vote is in dispute and fails, or if dispute is invalid, transfer the slashed stake to the reporter
            token.transfer(_thisDispute.disputedReporter, _thisDispute.slashedAmount); // todo: should be wrapped in require statement?
        }
        IRegistry.Parachain memory _parachain = registry.getById(_thisDispute.paraId);
        IParachainGovernance.VoteResult _convertedVoteResult = IParachainGovernance.VoteResult(uint8(_thisVote.result));
        reportVoteExecuted(_parachain, _disputeId, _convertedVoteResult);
        emit VoteExecuted(_disputeId, _thisVote.result);
    }

    // *****************************************************************************
    // *                                                                           *
    // *                               Getters                                     *
    // *                                                                           *
    // *****************************************************************************

    /**
     * @dev Determines if an address voted for a specific vote
     * @param _disputeId is the ID of the vote
     * @param _voter is the address of the voter to check for
     * @return bool of whether or note the address voted for the specific vote
     */
    function didVote(bytes32 _disputeId, address _voter) external view returns (bool) {
        return voteInfo[_disputeId][voteRounds[_disputeId]].voted[_voter];
    }

    function getDisputesByReporter(address _reporter) external view returns (bytes32[] memory) {
        return disputeIdsByReporter[_reporter];
    }

    /**
     * @dev Returns info on a dispute for a given ID
     * @param _disputeId is the ID of a specific dispute
     * @return bytes32 of the data ID of the dispute
     * @return uint256 of the timestamp of the dispute
     * @return bytes memory of the value being disputed
     * @return address of the reporter being disputed
     */
    function getDisputeInfo(bytes32 _disputeId) external view returns (bytes32, uint256, bytes memory, address) {
        Dispute storage _d = disputeInfo[_disputeId];
        return (_d.queryId, _d.timestamp, _d.value, _d.disputedReporter);
    }

    /**
     * @dev Returns info on a vote for a given vote ID
     * @param _disputeId is the ID of a specific vote
     * @return bytes32 identifier hash of the vote
     * @return uint256[17] memory of the pertinent round info (vote rounds, start date, etc.)
     * @return bool memory of both whether or not the vote was executed
     * @return VoteResult result of the vote
     * @return address memory of the vote initiator
     */
    function getVoteInfo(bytes32 _disputeId)
        external
        view
        returns (bytes32, uint256[16] memory, bool, VoteResult, address)
    {
        Vote storage _v = voteInfo[_disputeId][voteRounds[_disputeId]];
        return (
            _v.identifierHash,
            [
                _v.voteRound,
                _v.startDate,
                _v.blockNumber,
                _v.tallyDate,
                _v.tokenholders.doesSupport,
                _v.tokenholders.against,
                _v.tokenholders.invalidQuery,
                _v.users.doesSupport,
                _v.users.against,
                _v.users.invalidQuery,
                _v.reporters.doesSupport,
                _v.reporters.against,
                _v.reporters.invalidQuery,
                _v.teamMultisig.doesSupport,
                _v.teamMultisig.against,
                _v.teamMultisig.invalidQuery
            ],
            _v.executed,
            _v.result,
            _v.initiator
        );
    }

    /**
     * @dev Returns an array of voting rounds for a given vote
     * @param _hash is the identifier hash for a vote
     * @return uint8 Number of voting rounds for a given disputeId
     */
    function getVoteRounds(bytes32 _hash) external view returns (uint8) {
        return voteRounds[_hash];
    }

    /**
     * @dev Returns the total number of votes cast by an address
     * @param _voter is the address of the voter to check for
     * @return uint256 of the total number of votes cast by the voter
     */
    function getVoteTallyByAddress(address _voter) external view returns (uint256) {
        return voteTallyByAddress[_voter];
    }
}
