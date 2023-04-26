// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "./helpers/TestToken.sol";
import {StubXcmUtils} from "./helpers/StubXcmUtils.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import "../src/ParachainStaking.sol";
import "../src/ParachainGovernance.sol";

contract ParachainGovernanceTest is Test {
    TestToken public token;
    ParachainRegistry public registry;
    ParachainStaking public staking;
    ParachainGovernance public gov;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);
    address public fakeTeamMultiSig = address(0x3333);

    // create fake dispute initiation inputs
    address public bob = address(0x4444);
    address public alice = address(0x5555);
    bytes public bobsFakeAccount = abi.encodePacked(bob, uint256(4444));
    bytes32 fakeQueryId = keccak256(abi.encode("SpotPrice", abi.encode("btc", "usd")));
    uint256 fakeTimestamp = block.timestamp;
    bytes fakeValue = abi.encode(100_000 * 10 ** 8);
    bytes32 fakeDisputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));
    address fakeDisputedReporter = bob;
    address fakeDisputeInitiator = alice;
    uint256 fakeSlashAmount = 50;

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 20;

    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        staking = new ParachainStaking(address(registry), address(token));
        gov = new ParachainGovernance(address(registry), fakeTeamMultiSig);

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
        deployPrecompile("StubXcmUtils.sol", XCM_UTILS_ADDRESS);

        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId, fakePalletInstance, paraOwner);

        vm.prank(paraOwner);
        registry.register(fakeParaId, fakePalletInstance);

        gov.init(address(staking));
        staking.init(address(gov));

        // Fund disputer/disputed
        token.mint(bob, 100);
        token.mint(alice, 100);
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

    function testConstructor() public {
        assertEq(address(gov.owner()), address(this));
        assertEq(address(gov.parachainStaking()), address(staking));
        assertEq(address(gov.token()), address(token));
    }

    function testInit() public {
        // Check that only the owner can call init
        vm.prank(bob);
        vm.expectRevert("not owner");
        gov.init(address(staking));

        // Check that init can only be called once
        vm.expectRevert("parachainStaking address already set");
        gov.init(address(staking));

        // Ensure can't pass in zero address
        ParachainGovernance gov2 = new ParachainGovernance(address(registry), fakeTeamMultiSig);
        vm.expectRevert("parachainStaking address can't be zero address");
        gov2.init(address(0));

        // Ensure staking and token addresses updated
        assertEq(address(gov2.parachainStaking()), address(0));
        assertEq(address(gov2.token()), address(0));
        gov2.init(address(staking));
        assertEq(address(gov2.parachainStaking()), address(staking));
        assertEq(address(gov2.token()), address(token));
    }

    function testBeginParachainDispute() public {
        // Check that only the owner can call beginParachainDispute
        vm.startPrank(bob);
        vm.expectRevert("not owner");
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        vm.stopPrank();

        // Reporter deposits stake
        vm.startPrank(bob);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();
        assertEq(token.balanceOf(address(staking)), 100);
        assertEq(token.balanceOf(address(gov)), 0);
        assertEq(token.balanceOf(bob), 0);
        (, uint256 stakedBalanceBefore,,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(stakedBalanceBefore, 100);

        // Successfully begin dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        // Check reporter was slashed
        (, uint256 _stakedBalance,,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_stakedBalance, 50);
        assertEq(token.balanceOf(address(staking)), 50);
        assertEq(token.balanceOf(address(gov)), fakeSlashAmount);

        // Block disputes on old values
        vm.warp(block.timestamp + 3 days);
        uint256 oldTimestamp = block.timestamp - 12 hours;
        vm.prank(paraOwner);
        vm.expectRevert("Dispute must be started within reporting lock time");
        gov.beginParachainDispute(
            fakeQueryId, oldTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        // Prevent new vote rounds if previous round has not been tallied
        vm.prank(paraOwner);
        vm.expectRevert("New vote round window has elapsed");
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        // Ensure new vote rounds must be started within 2 days of the previous round
        vm.prank(bob);
        bytes32 _disputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));
        gov.vote(_disputeId, false, false);
        gov.tallyVotes(_disputeId);
        // start new round
        vm.warp(block.timestamp + 3 days);
        vm.prank(paraOwner);
        vm.expectRevert("New vote round window has elapsed");
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        // Prevent new vote rounds if previous round has been executed
        gov.executeVote(_disputeId);
        vm.warp(block.timestamp - 3 days);
        vm.prank(paraOwner);
        vm.expectRevert("Previous round must not be executed");
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
    }

    function testVote() public {
        // Try voting for nonexistent dispute
        vm.startPrank(bob);
        vm.expectRevert("Vote does not exist");
        gov.vote(fakeDisputeId, true, true);
        vm.stopPrank();

        // Reporter deposits stake
        vm.startPrank(bob);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();

        // Create dispute
        vm.startPrank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        vm.stopPrank();

        // Vote successfully
        token.mint(bob, 22);
        vm.startPrank(bob);
        bytes32 realDisputeId = gov.getDisputesByReporter(bob)[0];
        gov.vote(realDisputeId, true, true);
        bool voted = gov.didVote(realDisputeId, bob);
        assert(voted);

        // Try voting twice
        vm.expectRevert("Sender has already voted");
        gov.vote(realDisputeId, true, true);
        vm.stopPrank();

        // Check vote info
        (, uint256[16] memory voteInfo,,,) = gov.getVoteInfo(realDisputeId, 1);
        assertEq(voteInfo[0], 1); // voteRound
        assertEq(voteInfo[1], 1); // startDate
        assertEq(voteInfo[2], 1); // blockNumber
        assertEq(voteInfo[3], 0); // tallyDate
        assertEq(voteInfo[4], 72); // tokenholders.doesSupport (50 staked + 22 minted above)
        assertEq(voteInfo[5], 0); // tokenholders.against
        assertEq(voteInfo[6], 0); // tokenholders.invalidQuery
        assertEq(voteInfo[7], 0); // users.doesSupport
        assertEq(voteInfo[8], 0); // users.against
        assertEq(voteInfo[9], 0); // users.invalidQuery
        assertEq(voteInfo[10], 0); // reporters.doesSupport
        assertEq(voteInfo[11], 0); // reporters.against
        assertEq(voteInfo[12], 0); // reporters.invalidQuery
        assertEq(voteInfo[13], 0); // teamMultisig.doesSupport
        assertEq(voteInfo[14], 0); // teamMultisig.against
        assertEq(voteInfo[15], 0); // teamMultisig.invalidQuery

        // tally vote
        vm.warp(block.timestamp + 1 days);
        gov.tallyVotes(realDisputeId);

        // Ensure can't vote after tally
        vm.expectRevert("Vote has already been tallied");
        gov.vote(realDisputeId, true, true);
    }

    function testVoteParachain() public {
        // Reporter deposits stake
        vm.startPrank(bob);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();

        // Create dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        // Prevent incorrect origin
        vm.prank(bob);
        vm.expectRevert("not owner");
        gov.voteParachain(fakeDisputeId, 1, 2, 3, 4, 5, 6);

        // Prevent incorrect disputeId
        vm.prank(paraOwner);
        vm.expectRevert("invalid dispute identifier");
        gov.voteParachain(fakeDisputeId, 1, 2, 3, 4, 5, 6);

        // Vote successfully
        bytes32 realDisputeId = gov.getDisputesByReporter(bob)[0];
        vm.prank(paraOwner);
        gov.voteParachain(realDisputeId, 1, 2, 3, 4, 5, 6);

        // Check vote info
        (, uint256[16] memory voteInfo,,,) = gov.getVoteInfo(realDisputeId, 1);
        assertEq(voteInfo[0], 1); // voteRound
        assertEq(voteInfo[1], 1); // startDate
        assertEq(voteInfo[2], 1); // blockNumber
        assertEq(voteInfo[3], 0); // tallyDate
        assertEq(voteInfo[4], 0); // tokenholders.doesSupport
        assertEq(voteInfo[5], 0); // tokenholders.against
        assertEq(voteInfo[6], 0); // tokenholders.invalidQuery
        assertEq(voteInfo[7], 1); // users.doesSupport
        assertEq(voteInfo[8], 2); // users.against
        assertEq(voteInfo[9], 3); // users.invalidQuery
        assertEq(voteInfo[10], 4); // reporters.doesSupport
        assertEq(voteInfo[11], 5); // reporters.against
        assertEq(voteInfo[12], 6); // reporters.invalidQuery
        assertEq(voteInfo[13], 0); // teamMultisig.doesSupport
        assertEq(voteInfo[14], 0); // teamMultisig.against
        assertEq(voteInfo[15], 0); // teamMultisig.invalidQuery

        // tally vote
        vm.warp(block.timestamp + 1 days);
        gov.tallyVotes(realDisputeId);

        // Ensure can't vote after tally
        vm.prank(paraOwner);
        vm.expectRevert("Vote has already been tallied");
        gov.voteParachain(realDisputeId, 1, 2, 3, 4, 5, 6);
    }

    function testTallyVotes() public {
        // Reporter deposits stake
        vm.startPrank(bob);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();

        // Create dispute
        vm.startPrank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        vm.stopPrank();

        // Vote successfully
        token.mint(bob, 22);
        vm.startPrank(bob);
        bytes32 realDisputeId = gov.getDisputesByReporter(bob)[0];
        gov.vote(realDisputeId, true, true);
        vm.stopPrank();

        // Try to tally votes for non-existent vote
        vm.prank(bob);
        vm.expectRevert("Vote does not exist");
        gov.tallyVotes(fakeDisputeId);

        // Try to tally votes before voting time over
        vm.startPrank(paraOwner);
        vm.expectRevert("Time for voting has not elapsed");
        gov.tallyVotes(realDisputeId);

        // Tally votes
        uint256 tallyDate = block.timestamp + 7 days;
        vm.warp(tallyDate);
        gov.tallyVotes(realDisputeId);
        vm.stopPrank();

        // Check vote info
        (, uint256[16] memory voteInfo,,,) = gov.getVoteInfo(realDisputeId, 1);
        assertEq(voteInfo[3], tallyDate); // tallyDate
        assertEq(voteInfo[4], 72); // tokenholders.doesSupport

        // Ensure can't tally for unique vote more than once
        vm.prank(bob);
        vm.expectRevert("Vote has already been tallied");
        gov.tallyVotes(realDisputeId);
    }

    function testExecuteVote() public {
        // Ensure can't execute non-existent vote
        vm.prank(bob);
        vm.expectRevert("Vote does not exist");
        gov.executeVote(fakeDisputeId);

        // Reporter deposits stake
        vm.startPrank(bob);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();

        // Create dispute
        vm.startPrank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        vm.stopPrank();
        // Check gov contract balance
        assertEq(token.balanceOf(address(gov)), fakeSlashAmount);

        // Vote successfully
        token.mint(alice, 22);
        vm.startPrank(alice);
        bytes32 realDisputeId = gov.getDisputesByReporter(bob)[0];
        gov.vote(realDisputeId, true, true);
        vm.stopPrank();

        token.mint(bob, 33);
        vm.startPrank(bob);
        gov.vote(realDisputeId, false, true);
        vm.stopPrank();

        // Ensure vote not executed before vote tallied
        vm.prank(bob);
        vm.expectRevert("Vote must be tallied");
        gov.executeVote(realDisputeId);

        // todo: unsure how to test "Must be the final vote"

        // Tally votes
        uint256 tallyDate = block.timestamp + 7 days;
        vm.warp(tallyDate);
        gov.tallyVotes(realDisputeId);
        vm.stopPrank();

        // Three days pass before executing vote
        vm.warp(tallyDate + 3 days);

        // Execute vote
        vm.startPrank(paraOwner);
        gov.executeVote(realDisputeId);
        vm.stopPrank();

        // Ensure can't execute twice for same vote
        vm.prank(bob);
        vm.expectRevert("Vote has already been executed");
        gov.executeVote(realDisputeId);

        // todo: how test fee transfer failures?
    }

    function testDidVote() public {
        // Stake
        vm.startPrank(bob);
        token.mint(bob, 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();

        // Create dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        // Vote
        vm.startPrank(alice);
        bytes32 realDisputeId = gov.getDisputesByReporter(bob)[0];
        gov.vote(realDisputeId, true, true);
        vm.stopPrank();

        // Check didVote
        assertEq(gov.didVote(realDisputeId, alice), true);
        assertEq(gov.didVote(realDisputeId, bob), false);
    }

    function testGetDisputesByReporter() public {
        // Stake
        vm.startPrank(bob);
        token.mint(bob, 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();

        // Open dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        // Check disputes
        bytes32 realDisputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));
        bytes32[] memory disputes = gov.getDisputesByReporter(bob);
        assertEq(disputes.length, 1);
        assertEq(disputes[0], realDisputeId);

        // Check no disputes for undisputed reporter
        bytes32[] memory disputes2 = gov.getDisputesByReporter(alice);
        assertEq(disputes2.length, 0);
    }

    function testGetDisputeInfo() public {
        // Stake
        vm.startPrank(bob);
        token.mint(bob, 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();

        // Open dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        // Check dispute info
        bytes32 realDisputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));
        (bytes32 _qid, uint256 _ts, bytes memory _val, address _reporter) = gov.getDisputeInfo(realDisputeId);
        assertEq(_qid, fakeQueryId);
        assertEq(_ts, fakeTimestamp);
        assertEq(_val, fakeValue);
        assertEq(_reporter, fakeDisputedReporter);
    }
}
