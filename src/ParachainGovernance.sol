pragma solidity ^0.8.3;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Parachain } from "./Parachain.sol";
// import { IRegistry, ParachainRegistry, ParachainNotRegistered, NotOwner } from "./ParachainRegistry.sol";
import { IRegistry, ParachainRegistry } from "./ParachainRegistry.sol";
import { IParachainStaking } from "./ParachainStaking.sol";


/**
 @author Tellor Inc.
 @title Parachain Governance
 @dev This is a governance contract to be used with ParachainStaking. It resolves disputes
 * and votes sent from oracle consumer chains.
*/
contract ParachainGovernance is Parachain {
    // Storage
    address public owner;
    IParachainStaking public parachainStaking;
    IERC20 public token; // token used for dispute fees, same as reporter staking token
    address public teamMultisig; // address of team multisig wallet, one of four stakeholder groups
    uint256 public voteCount; // total number of votes initiated
    bytes32 public autopayAddrsQueryId =
    keccak256(abi.encode("AutopayAddresses", abi.encode(bytes("")))); // query id for autopay addresses array
    mapping(bytes32 => Dispute) private disputeInfo; // mapping of dispute IDs to the details of the dispute
    mapping(bytes32 => Vote) private voteInfo; // mapping of dispute IDs to the details of the vote
    mapping(bytes32 => bytes32[]) private voteRounds; // mapping of vote identifier hashes to an array of dispute IDs
    mapping(address => uint256) private voteTallyByAddress; // mapping of addresses to the number of votes they have cast
    mapping(address => bytes32[]) private disputeIdsByReporter; // mapping of reporter addresses to an array of dispute IDs

    enum VoteResult {
        FAILED,
        PASSED,
        INVALID
    } // status of a potential vote

    // Structs
    struct Dispute {
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
        uint256 fee; // fee paid to initiate the vote round
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
    event VoteTallied(
        bytes32 _disputeId,
        VoteResult _result,
        address _initiator,
        address _reporter
    ); // Emitted when all casting for a vote is tallied
    event ParachainVoted(bytes32, uint256[] _vote);
    event Voted(
        uint32 _paraId,
        bytes32 _queryId,
        uint256 _timestamp,
        bool _supports,
        address _voter,
        bool _invalidQuery
    ); // Emitted when an individual staker or the multisig casts their vote

    modifier onlyOwner {
        // if (msg.sender != owner) revert NotOwner();
        require(msg.sender == owner, "not owner");
        _;
    }

    /**
     * @dev Initializes contract parameters
     * @param _registry address of ParachainRegistry contract
     * @param _parachainStaking address of ParachainStaking contract
     * @param _teamMultiSig address of tellor team multisig, one of four voting
     * stakeholder groups
     */
    constructor(
        address _registry,
        address payable _parachainStaking,
        address _teamMultiSig
        )
        Parachain(_registry) 
    {
        parachainStaking = IParachainStaking(_parachainStaking);
        token = IERC20(parachainStaking.getTokenAddress());
        teamMultisig = _teamMultiSig;
    }

    /**
    * @dev Start dispute/vote for a specific parachain
    // Trusts that the corresponding value for the supplied query identifier and timestamp 
    // exists on the consumer parachain, that it has been removed during dispute initiation, 
    // and that a dispute fee has been locked.
    * @param _disputeId bytes32 Unique identifier for this dispute
    * @param _value bytes Value disputed
    * @param _disputedReporter address Reporter who submitted the disputed value
    * @param _disputeInitiator address Initiator who started the dispute/proposal
    * @param _slashAmount uint256 Amount of tokens to be slashed of staker
    */
    function beginParachainDispute(
        bytes32 _disputeId,
        bytes calldata _value,
        address _disputedReporter,
        address _disputeInitiator,
        uint256 _disputeFee,
        uint256 _slashAmount
        ) external {
        bytes memory _disputeIdBytes = abi.encode(_disputeId);
        (uint32 _paraId, bytes32 _queryId, uint256 _timestamp) = abi.decode(_disputeIdBytes, (uint32, bytes32, uint256));
        // Ensure parachain is registered & sender is parachain owner
        address parachainOwner = registry.owner(_paraId);
        require(parachainOwner != address(0x0), "parachain not registered");
        require(msg.sender == parachainOwner, "not owner");

        // Create unique identifier for this dispute
        // todo: remove this, but throws "stack too deep" error if removed
        bytes32 _disputeId = keccak256(abi.encodePacked(_paraId, _queryId, _timestamp));
        // Push new vote round
        voteRounds[_disputeId].push(_disputeId);

        // Create new vote and dispute
        Vote storage _thisVote = voteInfo[_disputeId];
        Dispute storage _thisDispute = disputeInfo[_disputeId];

        // Set dispute information
        _thisDispute.queryId = _queryId;
        _thisDispute.timestamp = _timestamp;
        _thisDispute.disputedReporter = _disputedReporter;
        // Set vote information
        _thisVote.identifierHash = _disputeId;
        _thisVote.initiator = _disputeInitiator;
        _thisVote.blockNumber = block.number; 
        _thisVote.startDate = block.timestamp; // This is correct bc consumer parachain must submit votes before voting period ends
        _thisVote.voteRound = voteRounds[_disputeId].length;
        
        disputeIdsByReporter[_disputedReporter].push(_disputeId);

        if (voteRounds[_disputeId].length == 1) { // Assumes voteRounds[_disputeId] will never be empty
            require(
                block.timestamp - _timestamp < 12 hours,
                "Dispute must be started within reporting lock time"
            );
            // slash a single stakeAmount from reporter
            _thisDispute.slashedAmount = parachainStaking.slashParachainReporter(
                _slashAmount,
                _paraId,
                _thisDispute.disputedReporter,
                address(this)
            );
            _thisDispute.value = _value;
        } else {
            bytes32 _prevId = voteRounds[_disputeId][voteRounds[_disputeId].length - 2];
            require(
                block.timestamp - voteInfo[_prevId].tallyDate < 1 days,
                "New dispute round must be started within a day"
            );
            _thisDispute.slashedAmount = disputeInfo[voteRounds[_disputeId][0]].slashedAmount;
            _thisDispute.value = disputeInfo[voteRounds[_disputeId][0]].value;
        }
        _thisVote.fee = _disputeFee;
        voteCount++;

        emit NewParachainDispute(
            _paraId,
            _queryId,
            _timestamp,
            _disputedReporter
        );
    }

    /**
     * @dev Enables the sender address (staker or multisig) to cast a vote
     * @param _disputeId is the unique identifier for the dispute
     * @param _supports is the address's vote: whether or not they support or are against
     * @param _validDispute is whether or not the dispute is valid (e.g. false if the dispute is invalid)
     */
    function vote(
        bytes32 _disputeId,
        bool _supports,
        bool _validDispute
    ) external {
        bytes memory _disputeIdBytes = abi.encode(_disputeId);
        (uint32 _paraId, bytes32 _queryId, uint256 _timestamp) = abi.decode(_disputeIdBytes, (uint32, bytes32, uint256));
        Vote storage _thisVote = voteInfo[_disputeId];

        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate == 0, "Vote has already been tallied");
        require(!_thisVote.voted[msg.sender], "Sender has already voted");

        // Update voting status and increment total queries for support, invalid, or against based on vote
        _thisVote.voted[msg.sender] = true;
        uint256 _tokenBalance = token.balanceOf(msg.sender);
        (, uint256 _stakedBalance, uint256 _lockedBalance, , , , , ) = parachainStaking.getParachainStakeInfo(_paraId, msg.sender);
        _tokenBalance += _stakedBalance + _lockedBalance;

        if (!_validDispute) { // If vote is invalid
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
        emit Voted(_paraId, _queryId, _timestamp, _supports, msg.sender, _validDispute);
    }

    /**
     * @dev Enables oracle consumer parachain to cast collated votes of its users and reporters for an open dispute.
     *      This function is called by the oracle consumer parachain, and can be called multiple times.
     * @param _disputeId is the ID of the dispute
     * @param _vote is the collated votes of the users & reporters on the oracle consumer parachain, 
     *        an array of uint256s representing the total tips contributed by users & total reports of reporters who voted for, 
     *        against, and invalid. Example:
     *        _vote = [totalTipsFor, totalTipsAgainst, totalTipsInvalid, totalReportsFor, totalReportsAgainst, totalReportsInvalid]
     */
    function voteParachain(bytes32 _disputeId, uint256[] memory _vote) external {
        bytes memory _disputeIdBytes = abi.encode(_disputeId);
        (uint32 _paraId, bytes32 _queryId, uint256 _timestamp) = abi.decode(_disputeIdBytes, (uint32, bytes32, uint256));
        address parachainOwner = registry.owner(_paraId);

        require(parachainOwner != address(0x0), "parachain not registered");
        require(msg.sender == parachainOwner, "not owner");

        Vote storage _thisVote = voteInfo[_disputeId];
        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate == 0, "Vote has already been tallied");

        // Update users vote
        _thisVote.users.doesSupport = _vote[0];
        _thisVote.users.against = _vote[1];
        _thisVote.users.invalidQuery = _vote[2];

        // Update reporters vote
        _thisVote.reporters.doesSupport = _vote[3];
        _thisVote.reporters.against = _vote[4];
        _thisVote.reporters.invalidQuery = _vote[5];

        emit ParachainVoted(_disputeId, _vote);
    }

        /**
     * @dev Tallies the votes and begins the 1 day challenge period
     * @param _disputeId is the ID of the vote being tallied
     */
    function tallyVotes(bytes32 _disputeId) external {
        Vote storage _thisVote = voteInfo[_disputeId];

        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate == 0, "Vote has already been tallied");

        // Determine appropriate vote duration dispute round
        // Vote time increases as rounds increase but only up to 6 days (withdrawal period)
        require(
            // uint256 _elapsedVotingTime = block.timestamp - _thisVote.startDate
            block.timestamp - _thisVote.startDate >= 1 days * _thisVote.voteRound ||
            block.timestamp - _thisVote.startDate >= 6 days, // todo: shouldn't it be <= 6 days? nick says correct
            "Time for voting has not elapsed"
        );
        // Get total votes from each separate stakeholder group.  This will allow
        // normalization so each group's votes can be combined and compared to
        // determine the vote outcome.
        uint256 _tokenVoteSum = _thisVote.tokenholders.doesSupport +
        _thisVote.tokenholders.against +
        _thisVote.tokenholders.invalidQuery;
        uint256 _reportersVoteSum = _thisVote.reporters.doesSupport +
        _thisVote.reporters.against +
        _thisVote.reporters.invalidQuery;
        uint256 _multisigVoteSum = _thisVote.teamMultisig.doesSupport +
        _thisVote.teamMultisig.against +
        _thisVote.teamMultisig.invalidQuery;
        uint256 _usersVoteSum = _thisVote.users.doesSupport +
        _thisVote.users.against +
        _thisVote.users.invalidQuery;
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
        uint256 _scaledDoesSupport = ((_thisVote.tokenholders.doesSupport *
        1e18) / _tokenVoteSum) +
        ((_thisVote.reporters.doesSupport * 1e18) / _reportersVoteSum) +
        ((_thisVote.teamMultisig.doesSupport * 1e18) / _multisigVoteSum) +
        ((_thisVote.users.doesSupport * 1e18) / _usersVoteSum);
        uint256 _scaledAgainst = ((_thisVote.tokenholders.against * 1e18) /
        _tokenVoteSum) +
        ((_thisVote.reporters.against * 1e18) / _reportersVoteSum) +
        ((_thisVote.teamMultisig.against * 1e18) / _multisigVoteSum) +
        ((_thisVote.users.against * 1e18) / _usersVoteSum);
        uint256 _scaledInvalid = ((_thisVote.tokenholders.invalidQuery * 1e18) /
        _tokenVoteSum) +
        ((_thisVote.reporters.invalidQuery * 1e18) / _reportersVoteSum) +
        ((_thisVote.teamMultisig.invalidQuery * 1e18) / _multisigVoteSum) +
        ((_thisVote.users.invalidQuery * 1e18) / _usersVoteSum);

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
        emit VoteTallied(
            _disputeId,
            _thisVote.result,
            _thisVote.initiator,
            disputeInfo[_disputeId].disputedReporter
        );
    }

    /**
     * @dev Executes vote and transfers corresponding balances to initiator/reporter
     * @param _disputeId is the ID of the vote being executed
     */
    function executeVote(bytes32 _disputeId) external {
        Vote storage _thisVote = voteInfo[_disputeId];

        require(_thisVote.identifierHash == _disputeId, "Vote does not exist");
        require(_thisVote.tallyDate > 0, "Vote must be tallied");
        require(!_thisVote.executed, "Vote has already been executed");
        // Ensure vote must be final vote and that time has to be pass (86400 = 24 * 60 * 60 for seconds in a day)
        // todo: what exactly is this comment saying? ^
        require(
            voteRounds[_thisVote.identifierHash].length == _thisVote.voteRound,
            "Must be the final vote"
        );
        //The time  has to pass after the vote is tallied
        require(
            block.timestamp - _thisVote.tallyDate >= 1 days,
            "1 day has to pass after tally to allow for disputes"
        );
        _thisVote.executed = true;
        Dispute storage _thisDispute = disputeInfo[_disputeId];
        uint256 _i;
        bytes32 _voteID;
        if (_thisVote.result == VoteResult.PASSED) {
            // If vote is in dispute and passed, iterate through each vote round and transfer the dispute to initiator
            for (
                _i = voteRounds[_thisVote.identifierHash].length;
                _i > 0;
                _i--
            ) {
                _voteID = voteRounds[_thisVote.identifierHash][_i - 1];
                _thisVote = voteInfo[_voteID];
                // If the first vote round, also make sure to transfer the reporter's slashed stake to the initiator
                if (_i == 1) {
                    token.transfer(
                        _thisVote.initiator,
                        _thisDispute.slashedAmount
                    );
                }
                token.transfer(_thisVote.initiator, _thisVote.fee);
            }
        } else if (_thisVote.result == VoteResult.INVALID) {
            // If vote is in dispute and is invalid, iterate through each vote round and transfer the dispute fee to initiator
            for (
                _i = voteRounds[_thisVote.identifierHash].length;
                _i > 0;
                _i--
            ) {
                _voteID = voteRounds[_thisVote.identifierHash][_i - 1];
                _thisVote = voteInfo[_voteID];
                token.transfer(_thisVote.initiator, _thisVote.fee);
            }
            // Transfer slashed tokens back to disputed reporter
            token.transfer(
                _thisDispute.disputedReporter,
                _thisDispute.slashedAmount
            );
        } else if (_thisVote.result == VoteResult.FAILED) {
            // If vote is in dispute and fails, iterate through each vote round and transfer the dispute fee to disputed reporter
            uint256 _reporterReward = 0;
            for (
                _i = voteRounds[_thisVote.identifierHash].length;
                _i > 0;
                _i--
            ) {
                _voteID = voteRounds[_thisVote.identifierHash][_i - 1];
                _thisVote = voteInfo[_voteID];
                _reporterReward += _thisVote.fee;
            }
            _reporterReward += _thisDispute.slashedAmount;
            token.transfer(_thisDispute.disputedReporter, _reporterReward);
        }
        emit VoteExecuted(_disputeId, voteInfo[_disputeId].result);
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
    function didVote(bytes32 _disputeId, address _voter)
    external
    view
    returns (bool)
    {
        return voteInfo[_disputeId].voted[_voter];
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
    function getDisputeInfo(bytes32 _disputeId)
    external
    view
    returns (
        bytes32,
        uint256,
        bytes memory,
        address
    )
    {
        Dispute storage _d = disputeInfo[_disputeId];
        return (_d.queryId, _d.timestamp, _d.value, _d.disputedReporter);
    }

    /**
     * @dev Returns the total number of votes
     * @return uint256 of the total number of votes
     */
    function getVoteCount() external view returns (uint256) {
        return voteCount;
    }

    /**
     * @dev Returns info on a vote for a given vote ID
     * @param _disputeId is the ID of a specific vote
     * @return bytes32 identifier hash of the vote
     * @return uint256[17] memory of the pertinent round info (vote rounds, start date, fee, etc.)
     * @return bool memory of both whether or not the vote was executed
     * @return VoteResult result of the vote
     * @return address memory of the vote initiator
     */
    function getVoteInfo(bytes32 _disputeId)
    external
    view
    returns (
        bytes32,
        uint256[17] memory,
        bool,
        VoteResult,
        address
    )
    {
        Vote storage _v = voteInfo[_disputeId];
        return (
        _v.identifierHash,
        [
        _v.voteRound,
        _v.startDate,
        _v.blockNumber,
        _v.fee,
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
     * @return uint256[] memory dispute IDs of the vote rounds
     */
    function getVoteRounds(bytes32 _hash)
    external
    view
    returns (bytes32[] memory)
    {
        return voteRounds[_hash];
    }

    /**
     * @dev Returns the total number of votes cast by an address
     * @param _voter is the address of the voter to check for
     * @return uint256 of the total number of votes cast by the voter
     */
    function getVoteTallyByAddress(address _voter)
    external
    view
    returns (uint256)
    {
        return voteTallyByAddress[_voter];
    }

}