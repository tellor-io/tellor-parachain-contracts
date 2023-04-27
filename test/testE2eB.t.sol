// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./helpers/TestToken.sol";
import {StubXcmUtils} from "./helpers/StubXcmUtils.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import "../src/ParachainStaking.sol";
import "../src/ParachainGovernance.sol";
import "./helpers/TestParachain.sol";

contract E2ETestsB is Test {
    TestToken public token;
    ParachainRegistry public registry;
    ParachainStaking public staking;
    ParachainGovernance public gov;
    TestParachain public parachain;

    address public paraOwner = address(0x1111);
    address public paraOwner2 = address(0x1112);
    address public paraOwner3 = address(0x1113);
    address public fakeTeamMultiSig = address(0x3333);

    // create fake dispute initiation inputs
    address public bob = address(0x4444);
    address public alice = address(0x5555);
    address public daryl = address(0x6666);
    bytes32 fakeQueryId = keccak256(abi.encode("SpotPrice", abi.encode("btc", "usd")));
    uint256 fakeTimestamp = block.timestamp;
    bytes fakeValue = abi.encode(100_000 * 10 ** 8);
    uint256 fakeWeightToFee = 5000;
    // bytes32 fakeDisputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint32 public fakeParaId2 = 13;
    uint32 public fakeParaId3 = 14;

    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);
    XcmTransactorV2.Multilocation fakeFeeLocation;

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        staking = new ParachainStaking(address(registry), address(token));
        gov = new ParachainGovernance(address(registry), fakeTeamMultiSig);
        parachain = new TestParachain(address(registry));
        // setting feeLocation as native token of destination chain
        fakeFeeLocation = XcmTransactorV2.Multilocation(1, parachain.x1External(3000));

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
        deployPrecompile("StubXcmUtils.sol", XCM_UTILS_ADDRESS);

        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId, 8, paraOwner);
        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId2, 9, paraOwner2);
        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId3, 10, paraOwner3);

        // Register parachains
        vm.prank(paraOwner);
        registry.register(fakeParaId, 8, fakeWeightToFee, fakeFeeLocation);
        vm.prank(paraOwner2);
        registry.register(fakeParaId2, 9, fakeWeightToFee, fakeFeeLocation);
        vm.prank(paraOwner3);
        registry.register(fakeParaId3, 10, fakeWeightToFee, fakeFeeLocation);

        gov.init(address(staking));
        staking.init(address(gov));

        // Fund test accounts
        token.mint(bob, 100);
        token.mint(alice, 100);
        token.mint(daryl, 100);
        token.mint(fakeTeamMultiSig, 100);
    }

    // From https://book.getfoundry.sh/cheatcodes/get-code#examples
    function deployPrecompile(string memory _contract, address _address) private {
        // Deploy supplied contract
        bytes memory bytecode = abi.encodePacked(vm.getCode(_contract));
        address deployed;
        assembly {
            deployed := create(0, add(bytecode, 0x20), mload(bytecode))
        }
        // Set the bytecode of supplied precompile address
        vm.etch(_address, deployed.code);
    }

    function testExecuteVotesOnMultipleParachains() public {
        // Open identical disputes on different parachains.
        // Have multiple voting rounds for multiple disputes, with varying outcomes.
        // Execute votes for multiple disputes.
        // Check that all state is correctly updated & there's no cross-contamination between storage variables.

        // Skips voting rounds for parachain 2 bc cross-contamination would be evident with only 2 parachains (parachains 1 & 3), a
        // and checking for that third one would be redundant.

        // STAKE FOR PARACHAINS
        // stake for parachain 1
        vm.startPrank(bob);
        token.approve(address(staking), 1);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            1 // _amount
        );
        vm.stopPrank();
        // stake for parachain 2
        vm.startPrank(alice);
        token.approve(address(staking), 2);
        staking.depositParachainStake(
            fakeParaId2, // _paraId
            bytes("consumerChainAcct"), // _account
            2 // _amount
        );
        vm.stopPrank();
        // stake for parachain 3
        vm.startPrank(daryl);
        token.approve(address(staking), 3);
        staking.depositParachainStake(
            fakeParaId3, // _paraId
            bytes("consumerChainAcct"), // _account
            3 // _amount
        );
        vm.stopPrank();

        // Check balances
        (, uint256 _stakedBal, uint256 _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(1, _stakedBal + _lockedBal);
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId2, alice);
        assertEq(2, _stakedBal + _lockedBal);
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId3, daryl);
        assertEq(3, _stakedBal + _lockedBal);
        assertEq(token.balanceOf(address(bob)), 100 - 1);
        assertEq(token.balanceOf(address(alice)), 100 - 2);
        assertEq(token.balanceOf(address(daryl)), 100 - 3);

        // BEGIN DISPUTES
        // begin dispute for parachain 1
        vm.startPrank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            bob, // _disputedReporter
            alice, // _disputeInitiator
            3 // _slashAmount (more than what bob has staked)
        );
        vm.stopPrank();
        // begin dispute for parachain 2
        vm.startPrank(paraOwner2);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            alice, // _disputedReporter
            bob, // _disputeInitiator
            2 // _slashAmount (equal to what alice has staked)
        );
        vm.stopPrank();
        // begin dispute for parachain 3
        vm.startPrank(paraOwner3);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            daryl, // _disputedReporter
            alice, // _disputeInitiator
            1 // _slashAmount (less than what daryl has staked)
        );
        vm.stopPrank();

        // Check balances
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(0, _stakedBal + _lockedBal); // 1 - 3 = 0 (bob's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId2, alice);
        assertEq(0, _stakedBal + _lockedBal); // 2 - 2 = 0 (alice's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId3, daryl);
        assertEq(2, _stakedBal + _lockedBal); // 3 - 1 = 2 (daryl's stake was slashed)
        assertEq(token.balanceOf(address(bob)), 100 - 1); // bob's token holdings should not have changed
        assertEq(token.balanceOf(address(alice)), 100 - 2); // alice's token holdings should not have changed
        assertEq(token.balanceOf(address(daryl)), 100 - 3); // daryl's token holdings should not have changed
        assertEq(token.balanceOf(address(gov)), 4); // 1 + 2 + 1 = 4 (gov contract should have received slashed tokens)

        // vote round 1 for parachain 1
        vm.prank(bob);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), false, true);
        vm.prank(alice);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), true, true);
        vm.prank(daryl);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), true, true);
        vm.prank(paraOwner);
        gov.voteParachain(
            keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), // _disputeId
            2, // _totalTipsFor
            1, // _totalTipsAgainst
            2, // _totalTipsInvalid
            3, // _totalReportsFor
            3, // _totalReportsAgainst
            1 // _totalReportsInvalid
        );
        // multisig does not vote
        // tally votes
        vm.warp(block.timestamp + 1 days);
        gov.tallyVotes(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)));
        // check vote state for parachain 1, round 1
        (, uint256[16] memory _voteInfo, bool _voteExecuted, ParachainGovernance.VoteResult _voteResult,) = gov
            .getVoteInfo(
            keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)))
        );
        assertEq(_voteInfo[0], 1); // vote round
        assertEq(_voteInfo[4], 100 + 100 - 2 - 3); // tokenholders does support (alice initial + daryl initial - alice's stake - daryl's stake)
        assertEq(_voteInfo[5], 99); // tokenholders against (bob initial balance - bob's stake)
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 2); // users does support
        assertEq(_voteInfo[8], 1); // users against
        assertEq(_voteInfo[9], 2); // users invalid query
        assertEq(_voteInfo[10], 3); // reporters does support
        assertEq(_voteInfo[11], 3); // reporters against
        assertEq(_voteInfo[12], 1); // reporters invalid query
        assertEq(_voteInfo[13], 0); // team multisig does support (did not vote)
        assertEq(_voteInfo[14], 0); // team multisig against (did not vote)
        assertEq(_voteInfo[15], 0); // team multisig invalid query (did not vote)
        assertEq(_voteExecuted, false); // vote executed status
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.INVALID)); // vote result

        // check balances
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(0, _stakedBal + _lockedBal); // 1 - 3 = 0 (bob's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId2, alice);
        assertEq(0, _stakedBal + _lockedBal); // 2 - 2 = 0 (alice's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId3, daryl);
        assertEq(2, _stakedBal + _lockedBal); // 3 - 1 = 2 (daryl's stake was slashed)
        assertEq(token.balanceOf(address(bob)), 100 - 1); // bob's token holdings should not have changed
        assertEq(token.balanceOf(address(alice)), 100 - 2); // alice's token holdings should not have changed
        assertEq(token.balanceOf(address(daryl)), 100 - 3); // daryl's token holdings should not have changed

        // vote round 2 for parachain 1
        // open new vote round
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            bob, // _disputedReporter
            alice, // _disputeInitiator
            3 // _slashAmount
        );
        vm.prank(bob);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), false, true);
        vm.prank(alice);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), true, true);
        vm.prank(daryl);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), true, true);
        vm.prank(paraOwner);
        gov.voteParachain(
            keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), // _disputeId
            5, // _totalTipsFor
            0, // _totalTipsAgainst
            5, // _totalTipsInvalid
            12, // _totalReportsFoR
            6, // _totalReportsAgainst
            6 // _totalReportsInvalid
        );
        vm.prank(fakeTeamMultiSig);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), true, true);
        // vote round 1 for parachain 3
        // first vote round already open when dispute was initiated
        vm.prank(bob);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), true, true);
        vm.prank(alice);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), true, true);
        vm.prank(daryl);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), false, true); // daryl was disputed
        vm.prank(paraOwner3);
        gov.voteParachain(
            keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), // _disputeId
            0, // _totalTipsFor
            0, // _totalTipsAgainst
            7, // _totalTipsInvalid
            0, // _totalReportsFor
            0, // _totalReportsAgainst
            7 // _totalReportsInvalid
        );
        vm.prank(fakeTeamMultiSig);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), true, true);

        // tally votes for parachain 3
        vm.warp(block.timestamp + 1 days); // only 1 day must pass after initial vote round has commenced
        gov.tallyVotes(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)));
        // check vote state
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(
            keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)))
        );
        assertEq(_voteInfo[0], 1); // vote round
        assertEq(_voteInfo[4], 100 + 100 + 100 - 1 - 2); // tokenholders does support (bob initial + alice initial + multisig - bob's stake - alice's stake)
        assertEq(_voteInfo[5], 100 - 1); // tokenholders against (daryl initial balance - slash amount)
        assertEq(_voteInfo[6], 0); // tokenholders invalid (no invalid votes)
        assertEq(_voteInfo[7], 0); // users does support
        assertEq(_voteInfo[8], 0); // users against
        assertEq(_voteInfo[9], 7); // users invalid query
        assertEq(_voteInfo[10], 0); // reporters does support
        assertEq(_voteInfo[11], 0); // reporters against
        assertEq(_voteInfo[12], 7); // reporters invalid query
        assertEq(_voteInfo[13], 1); // team multisig does support
        assertEq(_voteInfo[14], 0); // team multisig against
        assertEq(_voteInfo[15], 0); // team multisig invalid query
        assertEq(_voteExecuted, false); // vote executed status
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.INVALID)); // vote result
        // open vote round 2 for parachain 3
        vm.prank(paraOwner3);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            daryl, // _disputedReporter
            alice, // _disputeInitiator
            1 // _slashAmount (less than what daryl has staked)
        );
        // tally votes for parachain 1
        vm.warp(block.timestamp + 1 days); // 2 days must have passed since last vote round, since this is round 2 for parachain 1
        gov.tallyVotes(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)));
        // check vote state
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(
            keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)))
        );
        assertEq(_voteInfo[0], 2); // vote round
        assertEq(_voteInfo[4], 100 + 100 + 100 - 2 - 3); // tokenholders does support (multisig + alice + daryl - alice slashed - daryl slashed)
        assertEq(_voteInfo[5], 99); // tokenholders against (bob initial balance - bob's stake)
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 5); // users does support
        assertEq(_voteInfo[8], 0); // users against
        assertEq(_voteInfo[9], 5); // users invalid query
        assertEq(_voteInfo[10], 12); // reporters does support
        assertEq(_voteInfo[11], 6); // reporters against
        assertEq(_voteInfo[12], 6); // reporters invalid query
        assertEq(_voteInfo[13], 1); // team multisig does support
        assertEq(_voteInfo[14], 0); // team multisig against
        assertEq(_voteInfo[15], 0); // team multisig invalid query
        assertEq(_voteExecuted, false); // vote executed status
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED)); // vote result

        // check balances
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(0, _stakedBal + _lockedBal); // 1 - 3 = 0 (bob's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId2, alice);
        assertEq(0, _stakedBal + _lockedBal); // 2 - 2 = 0 (alice's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId3, daryl);
        assertEq(2, _stakedBal + _lockedBal); // 3 - 1 = 2 (daryl's stake was slashed)
        assertEq(token.balanceOf(address(bob)), 100 - 1); // bob's token holdings should not have changed
        assertEq(token.balanceOf(address(alice)), 100 - 2); // alice's token holdings should not have changed
        assertEq(token.balanceOf(address(daryl)), 100 - 3); // daryl's token holdings should not have changed

        // vote round 2 for parachain 3
        vm.prank(daryl);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), false, true); // disputed reporter votes against
        vm.prank(alice);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), true, true); // dispute initiator votes for
        vm.prank(bob);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), true, true); // random tokenholder votes for
        vm.prank(fakeTeamMultiSig);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), false, true); // team multisig votes against
        vm.prank(paraOwner3);
        gov.voteParachain(
            keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), // _disputeId
            1, // _totalTipsFor
            0, // _totalTipsAgainst
            0, // _totalTipsInvalid
            0, // _totalReportsFor
            0, // _totalReportsAgainst
            0 // _totalReportsInvalid
        );
        // vote round 3 for parachain 1
        // open new vote
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            bob, // _disputedReporter
            alice, // _disputeInitiator
            3 // _slashAmount
        );
        // no one votes except the multisig
        vm.prank(fakeTeamMultiSig);
        gov.vote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)), true, false); // invalid dispute
        // tally votes for parachain 3 (round 2)
        vm.warp(block.timestamp + 2 days); // 2 days must have passed since the last vote round for parachain 3
        gov.tallyVotes(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)));
        // open vote round 3 for parachain 3
        vm.prank(paraOwner3);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            daryl, // _disputedReporter
            alice, // _disputeInitiator
            1 // _slashAmount (less than what daryl has staked)
        );
        // tally votes for parachain 1 (round 3)
        vm.warp(block.timestamp + 1 days); // 3 days must have passed since last vote round, since this is round 3 for parachain 1
        gov.tallyVotes(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)));

        // check vote state for parachain 1, vote round 3
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(
            keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)))
        );
        assertEq(_voteInfo[0], 3); // vote round
        assertEq(_voteInfo[4], 0); // tokenholders does support
        assertEq(_voteInfo[5], 0); // tokenholders against
        assertEq(_voteInfo[6], 100); // tokenholders invalid query (multisig balance)
        assertEq(_voteInfo[7], 0); // users does support
        assertEq(_voteInfo[8], 0); // users against
        assertEq(_voteInfo[9], 0); // users invalid query
        assertEq(_voteInfo[10], 0); // reporters does support
        assertEq(_voteInfo[11], 0); // reporters against
        assertEq(_voteInfo[12], 0); // reporters invalid query
        assertEq(_voteInfo[13], 0); // team multisig does support
        assertEq(_voteInfo[14], 0); // team multisig against
        assertEq(_voteInfo[15], 1); // team multisig invalid query
        assertEq(_voteExecuted, false); // vote executed status
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.INVALID)); // vote result

        // check vote state for parachain 3, vote round 2
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(
            keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp))) - 1 // -1 bc round 3 is the latest
        );
        assertEq(_voteInfo[0], 2); // vote round
        assertEq(_voteInfo[4], 100 + 100 - 1 - 2); // tokenholders does support (bob + alice - bob stake slashed - alice stake slashed)
        assertEq(_voteInfo[5], 100 + 97 + 2); // tokenholders against (multisig + daryl bal after staking + (daryl stake - slash amount for daryl)
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 1); // users does support
        assertEq(_voteInfo[8], 0); // users against
        assertEq(_voteInfo[9], 0); // users invalid query
        assertEq(_voteInfo[10], 0); // reporters does support
        assertEq(_voteInfo[11], 0); // reporters against
        assertEq(_voteInfo[12], 0); // reporters invalid query
        assertEq(_voteInfo[13], 0); // team multisig does support
        assertEq(_voteInfo[14], 1); // team multisig against
        assertEq(_voteInfo[15], 0); // team multisig invalid query
        assertEq(_voteExecuted, false); // vote executed status
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.FAILED)); // vote result

        // check balances
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(0, _stakedBal + _lockedBal); // 1 - 3 = 0 (bob's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId2, alice);
        assertEq(0, _stakedBal + _lockedBal); // 2 - 2 = 0 (alice's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId3, daryl);
        assertEq(2, _stakedBal + _lockedBal); // 3 - 1 = 2 (daryl's stake was slashed)
        assertEq(token.balanceOf(address(bob)), 100 - 1); // bob's token holdings should not have changed
        assertEq(token.balanceOf(address(alice)), 100 - 2); // alice's token holdings should not have changed
        assertEq(token.balanceOf(address(daryl)), 100 - 3); // daryl's token holdings should not have changed

        // Execute vote for parachain 1
        vm.warp(block.timestamp + 1 days);
        gov.executeVote(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)));
        // check vote result and executed status
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(
            keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp)))
        );
        assertEq(_voteExecuted, true);
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.INVALID)); // vote result

        // check slashed stake returned to reporter
        assertEq(token.balanceOf(address(bob)), 100); // balance before + slashed stake

        // submit votes for parachain 3 (round 3)
        vm.prank(daryl);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), false, true); // disputed reporter votes against
        vm.prank(alice);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), true, true); // dispute initiator votes for
        vm.prank(bob);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), true, true); // random tokenholder votes for
        vm.prank(fakeTeamMultiSig);
        gov.vote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), false, true); // team multisig votes against
        vm.prank(paraOwner3);
        gov.voteParachain(
            keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)), // _disputeId
            22, // _totalTipsFor
            0, // _totalTipsAgainst
            0, // _totalTipsInvalid
            33, // _totalReportsFor
            0, // _totalReportsAgainst
            0 // _totalReportsInvalid
        );
        // tally votes for parachain 3 (round 3)
        vm.warp(block.timestamp + 1 days); // 3 days elapsed since vote round opened
        gov.tallyVotes(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)));
        // check vote state for parachain 3, vote round 3
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(
            keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)))
        );
        assertEq(_voteInfo[0], 3); // vote round 3
        assertEq(_voteInfo[4], 100 + 100 - 2); // tokenholders for: (bob initial + alice initial - alice stake slashed)
        assertEq(_voteInfo[5], 100 + 100 - 1); // tokenholders against: (multisig initial + daryl initial - daryl slash amount))
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 22); // users for
        assertEq(_voteInfo[8], 0); // users against
        assertEq(_voteInfo[9], 0); // users invalid query
        assertEq(_voteInfo[10], 33); // reporters for
        assertEq(_voteInfo[11], 0); // reporters against
        assertEq(_voteInfo[12], 0); // reporters invalid query
        assertEq(_voteInfo[13], 0); // team multisig for
        assertEq(_voteInfo[14], 1); // team multisig against
        assertEq(_voteInfo[15], 0); // team multisig invalid query
        assertEq(_voteExecuted, false); // vote executed status
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED));

        // check balances
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(0, _stakedBal + _lockedBal); // 1 - 3 = 0 (bob's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId2, alice);
        assertEq(0, _stakedBal + _lockedBal); // 2 - 2 = 0 (alice's stake was slashed)
        (, _stakedBal, _lockedBal,,,,,,) = staking.getParachainStakerInfo(fakeParaId3, daryl);
        assertEq(2, _stakedBal + _lockedBal); // 3 - 1 = 2 (daryl's stake was slashed)
        assertEq(token.balanceOf(address(bob)), 100); // bob's stake was returned
        assertEq(token.balanceOf(address(alice)), 100 - 2); // alice's token holdings should not have changed
        assertEq(token.balanceOf(address(daryl)), 100 - 3); // daryl's token holdings should not have changed

        // Execute vote for parachain 3
        vm.warp(block.timestamp + 1 days);
        gov.executeVote(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)));
        // check vote result and executed status
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(
            keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)),
            gov.getVoteRounds(keccak256(abi.encode(fakeParaId3, fakeQueryId, fakeTimestamp)))
        );
        assertEq(_voteExecuted, true);
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED)); // vote result

        // check slashed stake returned to reporter
        assertEq(token.balanceOf(address(daryl)), 100 - 3); // initial balance - stake amount
        assertEq(token.balanceOf(address(alice)), 100 - 2 + 1); // initial balance - her stake amount + daryl's slashed amount
    }
}
