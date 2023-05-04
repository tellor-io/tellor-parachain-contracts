// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./helpers/TestToken.sol";
import "./helpers/TestParachain.sol";
import {StubXcmUtils} from "./helpers/StubXcmUtils.sol";

import "../src/ParachainRegistry.sol";
import "../src/ParachainStaking.sol";
import "../src/ParachainGovernance.sol";

contract E2ETests is Test {
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
    bytes public bobsFakeAccount = abi.encodePacked(bob, uint256(4444));
    bytes32 fakeQueryId = keccak256(abi.encode("SpotPrice", abi.encode("btc", "usd")));
    uint256 fakeTimestamp = block.timestamp;
    bytes fakeValue = abi.encode(100_000 * 10 ** 8);
    bytes32 fakeDisputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));
    address fakeDisputedReporter = bob;
    address fakeDisputeInitiator = alice;
    uint256 fakeSlashAmount = 50;
    uint256 public fakeWeightToFee = 5000;

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 100;

    uint32 public fakeParaId2 = 13;
    uint8 public fakePalletInstance2 = 9;
    uint256 public fakeStakeAmount2 = 75;

    uint32 public fakeParaId3 = 14;
    uint8 public fakePalletInstance3 = 10;
    uint256 public fakeStakeAmount3 = 50;

    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);

    XcmTransactorV2.Multilocation public fakeFeeLocation;

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

        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId, fakePalletInstance, paraOwner);
        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId2, fakePalletInstance2, paraOwner2);
        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId3, fakePalletInstance3, paraOwner3);

        // Register parachains
        vm.prank(paraOwner);
        registry.register(fakeParaId, fakePalletInstance, fakeWeightToFee, fakeFeeLocation);
        vm.prank(paraOwner2);
        registry.register(fakeParaId2, fakePalletInstance2, fakeWeightToFee, fakeFeeLocation);
        vm.prank(paraOwner3);
        registry.register(fakeParaId3, fakePalletInstance3, fakeWeightToFee, fakeFeeLocation);

        gov.init(address(staking));
        staking.init(address(gov));

        // Fund test accounts
        token.mint(bob, fakeStakeAmount * 2);
        token.mint(alice, 100);
        token.mint(daryl, 100);
        token.mint(fakeTeamMultiSig, 1000);
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

    function testMultipleDisputesSingleChain() public {
        // staked and multiple times disputed on one consumer parachain but keeps reporting on that chain
        uint256 _numDisputes = 5;
        uint256 initialBalance = token.balanceOf(address(bob));
        token.mint(bob, fakeStakeAmount * _numDisputes);
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount * _numDisputes);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount * _numDisputes // _amount
        );
        vm.stopPrank();
        (, uint256 stakedBalance, uint256 lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(lockedBalance, 0);
        assertEq(stakedBalance, fakeStakeAmount * _numDisputes);
        assertEq(token.balanceOf(address(bob)), initialBalance);

        // Dispute a few times
        uint256 _initialBalanceDisputer = token.balanceOf(address(alice));
        vm.startPrank(paraOwner);
        for (uint256 i = 0; i < _numDisputes; i++) {
            vm.warp(fakeTimestamp + i + 1);
            gov.beginParachainDispute(
                fakeQueryId, fakeTimestamp + i, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
            );
            (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
            console.log("dispute #%s lockedBalance: %s", i + 1, lockedBalance);
            console.log("dispute #%s stakedBalance: %s", i + 1, stakedBalance);
            assertEq(stakedBalance, fakeStakeAmount * _numDisputes - fakeSlashAmount * (i + 1));
        }
        vm.stopPrank();

        // Check state
        assertEq(token.balanceOf(address(alice)), _initialBalanceDisputer);

        // Assumes reporting is happening on the oracle parachain
    }

    function testMultipleDisputesDifferentChains() public {
        // Test multiple disputes on different parachains
        // Open disputes for identical values (same value, query id, & submission timestamp) on different parachains.
        // Ensure no cross contamination in gov/staking contracts.

        // deposit stakes for parachain 1
        uint256 _numDisputes = 5;
        uint256 initialBalance = token.balanceOf(address(bob));
        token.mint(bob, fakeStakeAmount * _numDisputes);
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount * _numDisputes);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount * _numDisputes // _amount
        );
        vm.stopPrank();
        (, uint256 stakedBalance, uint256 lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(lockedBalance, 0);
        assertEq(stakedBalance, fakeStakeAmount * _numDisputes);
        assertEq(token.balanceOf(address(bob)), initialBalance);

        // deposit stakes for parachain 2
        uint256 _numDisputes2 = 3;
        uint256 initialBalance2 = token.balanceOf(address(bob));
        token.mint(bob, fakeStakeAmount2 * _numDisputes2);
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount2 * _numDisputes2);
        staking.depositParachainStake(
            fakeParaId2, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount2 * _numDisputes2 // _amount
        );
        vm.stopPrank();
        (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId2, bob);
        assertEq(lockedBalance, 0);
        assertEq(stakedBalance, fakeStakeAmount2 * _numDisputes2);
        assertEq(token.balanceOf(address(bob)), initialBalance2);

        // deposit stakes for parachain 3
        uint256 _numDisputes3 = 2;
        uint256 initialBalance3 = token.balanceOf(address(bob));
        token.mint(bob, fakeStakeAmount3 * _numDisputes3);
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount3 * _numDisputes3);
        staking.depositParachainStake(
            fakeParaId3, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount3 * _numDisputes3 // _amount
        );
        vm.stopPrank();
        (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId3, bob);
        assertEq(lockedBalance, 0);
        assertEq(stakedBalance, fakeStakeAmount3 * _numDisputes3);
        assertEq(token.balanceOf(address(bob)), initialBalance3);

        // Dispute a few times for parachain 1
        vm.startPrank(paraOwner);
        for (uint256 i = 0; i < _numDisputes; i++) {
            vm.warp(fakeTimestamp + i + 1);
            gov.beginParachainDispute(
                fakeQueryId, fakeTimestamp + i, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
            );
            (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
            console.log("dispute #%s lockedBalance: %s", i + 1, lockedBalance);
            console.log("dispute #%s stakedBalance: %s", i + 1, stakedBalance);
            assertEq(stakedBalance, fakeStakeAmount * _numDisputes - fakeSlashAmount * (i + 1));
        }
        vm.stopPrank();
        assertEq(token.balanceOf(address(gov)), fakeSlashAmount * _numDisputes);

        // Dispute a few times for parachain 2
        uint256 _govBalance = token.balanceOf(address(gov));
        vm.startPrank(paraOwner2);
        for (uint256 i = 0; i < _numDisputes2; i++) {
            vm.warp(fakeTimestamp + i + 1);
            gov.beginParachainDispute(
                fakeQueryId, fakeTimestamp + i, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
            );
            (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId2, bob);
            console.log("dispute #%s lockedBalance: %s", i + 1, lockedBalance);
            console.log("dispute #%s stakedBalance: %s", i + 1, stakedBalance);
            assertEq(stakedBalance, fakeStakeAmount2 * _numDisputes2 - fakeSlashAmount * (i + 1));
        }
        vm.stopPrank();
        assertEq(token.balanceOf(address(gov)), _govBalance + fakeSlashAmount * _numDisputes2);

        // Dispute a few times for parachain 3
        _govBalance = token.balanceOf(address(gov));
        vm.startPrank(paraOwner3);
        for (uint256 i = 0; i < _numDisputes3; i++) {
            vm.warp(fakeTimestamp + i + 1);
            gov.beginParachainDispute(
                fakeQueryId, fakeTimestamp + i, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
            );
            (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId3, bob);
            console.log("dispute #%s lockedBalance: %s", i + 1, lockedBalance);
            console.log("dispute #%s stakedBalance: %s", i + 1, stakedBalance);
            assertEq(stakedBalance, fakeStakeAmount3 * _numDisputes3 - fakeSlashAmount * (i + 1));
        }
        vm.stopPrank();
        assertEq(token.balanceOf(address(gov)), _govBalance + fakeSlashAmount * _numDisputes3);
    }

    function testRequestWithdrawStakeThenDispute() public {
        /*
        simulate bad value placed, stake withdraw requested, dispute started on oracle consumer parachain
        */

        // Stake, then request stake withdrawal
        uint256 initialBalance = token.balanceOf(address(bob));
        (, uint256 stakedBalance, uint256 lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
        console.log("starting stakedBalance: %s", stakedBalance);
        console.log("starting lockedBalance: %s", lockedBalance);
        console.log("starting bob balance: %s", token.balanceOf(address(bob)));
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
        console.log("after staking stakedBalance: %s", stakedBalance);
        console.log("after staking lockedBalance: %s", lockedBalance);
        console.log("after staking bob balance: %s", token.balanceOf(address(bob)));
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            fakeStakeAmount // _amount
        );
        vm.stopPrank();
        (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
        console.log("after withdraw request stakedBalance: %s", stakedBalance);
        console.log("after withdraw request lockedBalance: %s", lockedBalance);
        console.log("after withdraw request bob balance: %s", token.balanceOf(address(bob)));
        assertEq(lockedBalance, fakeStakeAmount);
        assertEq(stakedBalance, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount);

        // Can assume bad value was submitted on oracle consumer parachain 🪄

        // Successfully begin dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        // Check reporter was slashed
        (, uint256 _stakedBalAfter, uint256 _lockedBalAfter) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_stakedBalAfter, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount);
        assertEq(_lockedBalAfter, fakeStakeAmount - fakeSlashAmount);

        assertEq(token.balanceOf(address(staking)), 50);
        assertEq(token.balanceOf(address(gov)), fakeSlashAmount);
    }

    function testMultipleStakeWithdrawRequestsDisputesOnMultipleChains() public {
        // simulate bad values places on multiple consumer parachains, stake withdraws requested across each consumer parachain, disputes started across each parachain
        console.log("---------------------------------- START TEST ----------------------------------");
        console.log(
            "simulate bad values places on multiple consumer parachains, stake withdraws requested across each consumer parachain, disputes started across each parachain"
        );

        uint256 balanceStakingContract = token.balanceOf(address(staking));
        uint256 balanceGovContract = token.balanceOf(address(gov));
        console.log("GENERAL INFO");
        console.log("Staking contract starting balance: ", balanceStakingContract);
        console.log("Gov contract starting balance: ", balanceGovContract);
        console.log("Slash amount for each parachain: ", fakeSlashAmount);
        console.log("\n");

        // Fund staker
        token.mint(bob, fakeStakeAmount2 + fakeStakeAmount3);
        assertEq(token.balanceOf(address(bob)), fakeStakeAmount * 2 + fakeStakeAmount2 + fakeStakeAmount3);

        // FOR 1ST PARACHAIN
        console.log("PARACHAIN #1");
        console.log("1st parachain stake amount: ", fakeStakeAmount);
        // Stake, then request stake withdrawal
        uint256 initialBalance = token.balanceOf(address(bob));
        console.log("bob balance before staking for 1st parachain: ", token.balanceOf(address(bob)));
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        console.log("bob balance after staking for 1st parachain: ", token.balanceOf(address(bob)));
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            fakeStakeAmount // _amount
        );
        vm.stopPrank();
        (, uint256 stakedBalance, uint256 lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(lockedBalance, fakeStakeAmount);
        assertEq(stakedBalance, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount);
        console.log("bob staked balance after requesting withdraw for 1st parachain: ", stakedBalance);
        console.log("bob locked balance after requesting withdraw for 1st parachain: ", lockedBalance);

        // Can assume bad value was submitted on oracle consumer parachain 🪄

        // Successfully begin dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        // Check reporter was slashed
        console.log("bob balance after dispute for 1st parachain: ", token.balanceOf(address(bob)));
        (, uint256 _stakedBalAfter, uint256 _lockedBalAfter) = staking.getParachainStakerInfo(fakeParaId, bob);
        console.log("bob staked balance after dispute for 1st parachain: ", _stakedBalAfter);
        console.log("bob locked balance after dispute for 1st parachain: ", _lockedBalAfter);
        assertEq(_stakedBalAfter, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount);
        assertEq(_lockedBalAfter, fakeStakeAmount - fakeSlashAmount);

        balanceStakingContract = token.balanceOf(address(staking));
        balanceGovContract = token.balanceOf(address(gov));
        console.log("Staking contract balance after dispute for 1st parachain: ", balanceStakingContract);
        console.log("Gov contract balance after dispute for 1st parachain: ", balanceGovContract);
        assertEq(balanceStakingContract, fakeStakeAmount - fakeSlashAmount);
        assertEq(balanceGovContract, fakeSlashAmount);
        console.log("\n");

        // FOR 2ND PARACHAIN
        console.log("PARACHAIN #2");
        console.log("2nd parachain stake amount: ", fakeStakeAmount2);
        // Stake, then request stake withdrawal
        initialBalance = token.balanceOf(address(bob));
        console.log("bob balance before staking for 2nd parachain: ", token.balanceOf(address(bob)));
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount2);
        staking.depositParachainStake(
            fakeParaId2, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount2 // _amount
        );
        console.log("bob balance after staking for 2nd parachain: ", token.balanceOf(address(bob)));
        staking.requestParachainStakeWithdraw(
            fakeParaId2, // _paraId
            fakeStakeAmount2 // _amount
        );
        vm.stopPrank();
        (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId2, bob);
        assertEq(lockedBalance, fakeStakeAmount2);
        assertEq(stakedBalance, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount2);
        console.log("bob staked balance after requesting withdraw for 2nd parachain: ", stakedBalance);
        console.log("bob locked balance after requesting withdraw for 2nd parachain: ", lockedBalance);

        // Can assume bad value was submitted on oracle consumer parachain 🪄

        // Successfully begin dispute
        vm.prank(paraOwner2);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        // Check reporter was slashed
        console.log("bob balance after dispute for 2nd parachain: ", token.balanceOf(address(bob)));
        (, _stakedBalAfter, _lockedBalAfter) = staking.getParachainStakerInfo(fakeParaId2, bob);
        console.log("bob staked balance after dispute for 2nd parachain: ", _stakedBalAfter);
        console.log("bob locked balance after dispute for 2nd parachain: ", _lockedBalAfter);
        assertEq(_stakedBalAfter, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount2);
        assertEq(_lockedBalAfter, fakeStakeAmount2 - fakeSlashAmount);

        balanceStakingContract = token.balanceOf(address(staking));
        balanceGovContract = token.balanceOf(address(gov));
        console.log("Staking contract balance after dispute for 2nd parachain: ", balanceStakingContract);
        console.log("Gov contract balance after dispute for 2nd parachain: ", balanceGovContract);
        assertEq(balanceStakingContract, (fakeStakeAmount + fakeStakeAmount2) - fakeSlashAmount * 2);
        assertEq(balanceGovContract, fakeSlashAmount * 2);
        console.log("\n");

        // FOR 3RD PARACHAIN
        console.log("PARACHAIN #3");
        // Stake, then request stake withdrawal
        initialBalance = token.balanceOf(address(bob));
        console.log("bob balance before staking for 3rd parachain: ", token.balanceOf(address(bob)));
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount3);
        staking.depositParachainStake(
            fakeParaId3, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount3 // _amount
        );
        console.log("bob balance after staking for 3rd parachain: ", token.balanceOf(address(bob)));
        staking.requestParachainStakeWithdraw(
            fakeParaId3, // _paraId
            fakeStakeAmount3 // _amount
        );
        vm.stopPrank();
        (, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId3, bob);
        console.log("bob staked balance after requesting withdraw for 3rd parachain: ", stakedBalance);
        console.log("bob locked balance after requesting withdraw for 3rd parachain: ", lockedBalance);
        assertEq(lockedBalance, fakeStakeAmount3);
        assertEq(stakedBalance, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount3);

        // Can assume bad value was submitted on oracle consumer parachain 🪄

        // Successfully begin dispute
        vm.prank(paraOwner3);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        // Check reporter was slashed
        console.log("bob balance after dispute for 3rd parachain: ", token.balanceOf(address(bob)));
        (, _stakedBalAfter, _lockedBalAfter) = staking.getParachainStakerInfo(fakeParaId3, bob);
        console.log("bob staked balance after dispute for 3rd parachain: ", _stakedBalAfter);
        console.log("bob locked balance after dispute for 3rd parachain: ", _lockedBalAfter);
        assertEq(_stakedBalAfter, 0);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount3);
        assertEq(_lockedBalAfter, fakeStakeAmount3 - fakeSlashAmount);

        balanceStakingContract = token.balanceOf(address(staking));
        balanceGovContract = token.balanceOf(address(gov));
        console.log("Staking contract balance after dispute for 3rd parachain: ", balanceStakingContract);
        console.log("Gov contract balance after dispute for 3rd parachain: ", balanceGovContract);
        assertEq(
            token.balanceOf(address(staking)),
            fakeStakeAmount + fakeStakeAmount2 + fakeStakeAmount3 - fakeSlashAmount * 3
        );
        assertEq(token.balanceOf(address(gov)), fakeSlashAmount * 3);

        console.log("---------------------------------- END TEST ----------------------------------");
        console.log("\n");
    }

    function testMultipleVotesOnDisputeAllPassing() public {
        // test multiple vote rounds on a dispute for one parachain, all passing

        // stake for parachain
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        vm.stopPrank();

        // begin initial dispute
        uint256 _startVote = block.timestamp;
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        bytes32 _disputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));

        // VOTE ROUND 1
        // reporter votes against the dispute
        uint256 _bobBalance = token.balanceOf(address(bob));
        (, uint256 _stakedBal, uint256 _lockedBal) = staking.getParachainStakerInfo(fakeParaId, bob);
        uint256 _bobTotalBalance = _bobBalance + _stakedBal + _lockedBal;
        vm.prank(bob);
        gov.vote(_disputeId, false, true);
        // random reporter votes against the dispute
        uint256 _darylBalance = token.balanceOf(address(daryl));
        (, _stakedBal, _lockedBal) = staking.getParachainStakerInfo(fakeParaId, daryl);
        uint256 _darylTotalBalance = _darylBalance + _stakedBal + _lockedBal;
        vm.prank(daryl);
        gov.vote(_disputeId, false, true);
        // multisig votes for the dispute
        uint256 _balTeamMultiSig = token.balanceOf(address(fakeTeamMultiSig));
        vm.prank(fakeTeamMultiSig);
        gov.vote(_disputeId, true, true);
        // parachain casts cumulative vote for users on oracle consumer parachain in favor of dispute
        vm.prank(paraOwner);
        gov.voteParachain(
            _disputeId,
            100, // _totalTipsFor
            100, // _totalTipsAgainst
            100, // _totalTipsInvalid
            100, // _totalReportsFor
            100, // _totalReportsAgainst
            100 // _totalReportsInvalid
        );
        // tally votes
        vm.warp(block.timestamp + 1 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, uint256[16] memory _voteInfo,, ParachainGovernance.VoteResult _voteResult,) = gov.getVoteInfo(_disputeId, 1);
        assertEq(_voteInfo[0], 1); // vote round
        assertEq(_voteInfo[1], _startVote); // start date
        assertEq(_voteInfo[2], block.number); // block number
        assertEq(_voteInfo[3], _startVote + 1 days); // tally date
        assertEq(_voteInfo[4], _balTeamMultiSig); // tokenholders does support
        assertEq(_voteInfo[5], _bobTotalBalance + _darylTotalBalance); // tokenholders against
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 100); // users does support
        assertEq(_voteInfo[8], 100); // users against
        assertEq(_voteInfo[9], 100); // users invalid query
        assertEq(_voteInfo[10], 100); // reporters does support
        assertEq(_voteInfo[11], 100); // reporters against
        assertEq(_voteInfo[12], 100); // reporters invalid query
        assertEq(_voteInfo[13], 1); // team multisig does support
        assertEq(_voteInfo[14], 0); // team multisig against
        assertEq(_voteInfo[15], 0); // team multisig invalid query
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED)); // vote result
        console.log("vote #1 result: ", uint8(_voteResult));

        // VOTE ROUND 2
        // reporter opens dispute again, starting another vote round
        _startVote = block.timestamp;
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 2);
        assertEq(_voteInfo[0], 2); // vote round
        // reporter votes against the dispute
        vm.prank(bob);
        gov.vote(_disputeId, false, true);
        // random reporter votes against the dispute
        vm.prank(daryl);
        gov.vote(_disputeId, false, true);
        // multisig votes for the dispute
        vm.prank(fakeTeamMultiSig);
        gov.vote(_disputeId, true, true);
        // parachain casts cumulative vote for users on oracle consumer parachain in favor of dispute
        vm.prank(paraOwner);
        gov.voteParachain(
            _disputeId,
            100, // _totalTipsFor
            100, // _totalTipsAgainst
            100, // _totalTipsInvalid
            100, // _totalReportsFor
            100, // _totalReportsAgainst
            100 // _totalReportsInvalid
        );
        // tally votes
        vm.warp(block.timestamp + 2 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 2);
        assertEq(_voteInfo[0], 2); // vote round
        assertEq(_voteInfo[1], _startVote); // start date
        assertEq(_voteInfo[2], block.number); // block number
        assertEq(_voteInfo[3], _startVote + 2 days); // tally date
        assertEq(_voteInfo[4], _balTeamMultiSig); // tokenholders does support
        assertEq(_voteInfo[5], _bobTotalBalance + _darylTotalBalance); // tokenholders against
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 100); // users does support
        assertEq(_voteInfo[10], 100); // reporters does support
        assertEq(_voteInfo[13], 1); // team multisig does support
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED)); // vote result
        console.log("vote #2 result: ", uint8(_voteResult));

        // VOTE ROUND 3
        // reporter opens dispute again, starting another vote round
        _startVote = block.timestamp;
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 3);
        assertEq(_voteInfo[0], 3); // vote round
        // reporter votes against the dispute
        vm.prank(bob);
        gov.vote(_disputeId, false, true);
        // random reporter votes against the dispute
        vm.prank(daryl);
        gov.vote(_disputeId, false, true);
        // multisig votes for the dispute
        vm.prank(fakeTeamMultiSig);
        gov.vote(_disputeId, true, true);
        // parachain casts cumulative vote for users on oracle consumer parachain in favor of dispute
        vm.prank(paraOwner);
        gov.voteParachain(
            _disputeId,
            100, // _totalTipsFor
            100, // _totalTipsAgainst
            100, // _totalTipsInvalid
            100, // _totalReportsFor
            100, // _totalReportsAgainst
            100 // _totalReportsInvalid
        );
        // tally votes
        vm.warp(block.timestamp + 3 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 3);
        assertEq(_voteInfo[0], 3); // vote round
        assertEq(_voteInfo[1], _startVote); // start date
        assertEq(_voteInfo[2], block.number); // block number
        assertEq(_voteInfo[3], _startVote + 3 days); // tally date
        assertEq(_voteInfo[4], _balTeamMultiSig); // tokenholders does support
        assertEq(_voteInfo[5], _bobTotalBalance + _darylTotalBalance); // tokenholders against
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 100); // users does support
        assertEq(_voteInfo[10], 100); // reporters does support
        assertEq(_voteInfo[13], 1); // team multisig does support
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED)); // vote result
        console.log("vote #3 result: ", uint8(_voteResult));

        // exectue vote
        vm.warp(block.timestamp + 3 days);
        gov.executeVote(_disputeId);
        (,, bool _voteExecuted,,) = gov.getVoteInfo(_disputeId, 3);
        assertEq(_voteExecuted, true);
    }

    function testMultipleVoteRoundsOverturnResult() public {
        // multiple vote rounds on a dispute, overturn result
        // do the same as testMultipleVotesOnDisputeAllPassing, but fail the vote in the last round

        // stake for parachain
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        vm.stopPrank();

        // begin initial dispute
        uint256 _startVote = block.timestamp;
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        bytes32 _disputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));

        // VOTE ROUND 1
        // reporter votes against the dispute
        uint256 _bobBalance = token.balanceOf(address(bob));
        (, uint256 _stakedBal, uint256 _lockedBal) = staking.getParachainStakerInfo(fakeParaId, bob);
        uint256 _bobTotalBalance = _bobBalance + _stakedBal + _lockedBal;
        vm.prank(bob);
        gov.vote(_disputeId, false, true);
        // random reporter votes against the dispute
        uint256 _darylBalance = token.balanceOf(address(daryl));
        (, _stakedBal, _lockedBal) = staking.getParachainStakerInfo(fakeParaId, daryl);
        uint256 _darylTotalBalance = _darylBalance + _stakedBal + _lockedBal;
        vm.prank(daryl);
        gov.vote(_disputeId, false, true);
        // multisig votes for the dispute
        uint256 _balTeamMultiSig = token.balanceOf(address(fakeTeamMultiSig));
        vm.prank(fakeTeamMultiSig);
        gov.vote(_disputeId, true, true);
        // parachain casts cumulative vote for users on oracle consumer parachain in favor of dispute
        vm.prank(paraOwner);
        gov.voteParachain(
            _disputeId,
            100, // _totalTipsFor
            100, // _totalTipsAgainst
            100, // _totalTipsInvalid
            100, // _totalReportsFor
            100, // _totalReportsAgainst
            100 // _totalReportsInvalid
        );
        // tally votes
        vm.warp(block.timestamp + 1 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, uint256[16] memory _voteInfo,, ParachainGovernance.VoteResult _voteResult,) = gov.getVoteInfo(_disputeId, 1);
        assertEq(_voteInfo[0], 1); // vote round
        assertEq(_voteInfo[1], _startVote); // start date
        assertEq(_voteInfo[2], block.number); // block number
        assertEq(_voteInfo[3], _startVote + 1 days); // tally date
        assertEq(_voteInfo[4], _balTeamMultiSig); // tokenholders does support
        assertEq(_voteInfo[5], _bobTotalBalance + _darylTotalBalance); // tokenholders against
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 100); // users does support
        assertEq(_voteInfo[8], 100); // users against
        assertEq(_voteInfo[9], 100); // users invalid query
        assertEq(_voteInfo[10], 100); // reporters does support
        assertEq(_voteInfo[11], 100); // reporters against
        assertEq(_voteInfo[12], 100); // reporters invalid query
        assertEq(_voteInfo[13], 1); // team multisig does support
        assertEq(_voteInfo[14], 0); // team multisig against
        assertEq(_voteInfo[15], 0); // team multisig invalid query
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED)); // vote result
        console.log("vote #1 result: ", uint8(_voteResult));

        // VOTE ROUND 2
        // reporter opens dispute again, starting another vote round
        _startVote = block.timestamp;
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 2);
        assertEq(_voteInfo[0], 2); // vote round
        // reporter votes against the dispute
        vm.prank(bob);
        gov.vote(_disputeId, false, true);
        // random reporter votes against the dispute
        vm.prank(daryl);
        gov.vote(_disputeId, false, true);
        // multisig votes for the dispute
        vm.prank(fakeTeamMultiSig);
        gov.vote(_disputeId, true, true);
        // parachain casts cumulative vote for users on oracle consumer parachain in favor of dispute
        vm.prank(paraOwner);
        gov.voteParachain(
            _disputeId,
            100, // _totalTipsFor
            100, // _totalTipsAgainst
            100, // _totalTipsInvalid
            100, // _totalReportsFor
            100, // _totalReportsAgainst
            100 // _totalReportsInvalid
        );
        // tally votes
        vm.warp(block.timestamp + 2 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 2);
        assertEq(_voteInfo[0], 2); // vote round
        assertEq(_voteInfo[1], _startVote); // start date
        assertEq(_voteInfo[2], block.number); // block number
        assertEq(_voteInfo[3], _startVote + 2 days); // tally date
        assertEq(_voteInfo[4], _balTeamMultiSig); // tokenholders does support
        assertEq(_voteInfo[5], _bobTotalBalance + _darylTotalBalance); // tokenholders against
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 100); // users does support
        assertEq(_voteInfo[10], 100); // reporters does support
        assertEq(_voteInfo[13], 1); // team multisig does support
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.PASSED)); // vote result
        console.log("vote #2 result: ", uint8(_voteResult));

        // VOTE ROUND 3
        // reporter opens dispute again, starting another vote round
        // vote fails
        _bobBalance = token.balanceOf(address(bob));
        _startVote = block.timestamp;
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 3);
        assertEq(_voteInfo[0], 3); // vote round
        // reporter votes against the dispute
        vm.prank(bob);
        gov.vote(_disputeId, false, true);
        // random reporter votes against the dispute
        vm.prank(daryl);
        gov.vote(_disputeId, false, true);
        // multisig votes for the dispute
        vm.prank(fakeTeamMultiSig);
        gov.vote(_disputeId, false, true);
        // cast cumulative vote for users on oracle consumer parachain
        vm.prank(paraOwner);
        gov.voteParachain(
            _disputeId,
            100, // _totalTipsFor
            100, // _totalTipsAgainst
            100, // _totalTipsInvalid
            100, // _totalReportsFor
            100, // _totalReportsAgainst
            100 // _totalReportsInvalid
        );
        // tally votes
        vm.warp(block.timestamp + 3 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, _voteInfo,, _voteResult,) = gov.getVoteInfo(_disputeId, 3);
        assertEq(_voteInfo[0], 3); // vote round
        assertEq(_voteInfo[1], _startVote); // start date
        assertEq(_voteInfo[2], block.number); // block number
        assertEq(_voteInfo[3], _startVote + 3 days); // tally date
        assertEq(_voteInfo[4], 0); // tokenholders does support
        assertEq(_voteInfo[5], _bobTotalBalance + _darylTotalBalance + _balTeamMultiSig); // tokenholders against
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 100); // users does support
        assertEq(_voteInfo[10], 100); // reporters does support
        assertEq(_voteInfo[13], 0); // team multisig does support
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.FAILED)); // vote result
        console.log("vote #3 result: ", uint8(_voteResult));

        // exectue vote
        vm.warp(block.timestamp + 3 days);
        gov.executeVote(_disputeId);
        (,, bool _voteExecuted,,) = gov.getVoteInfo(_disputeId, 3);
        assertEq(_voteExecuted, true);

        // check disputed reporter balance
        assertEq(token.balanceOf(address(fakeDisputedReporter)), _bobBalance + fakeSlashAmount);
    }

    function testNoVotesForDispute() public {
        // If no votes are cast, it should resolve to invalid and everyone should get refunded

        // stake for parachain
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        vm.stopPrank();

        // get balance reporter before slashing
        uint256 _bobBalance = token.balanceOf(address(bob));

        // begin initial dispute
        uint256 _startVote = block.timestamp;
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );
        bytes32 _disputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));

        // VOTE ROUND 1
        // tally votes
        vm.warp(block.timestamp + 1 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, uint256[16] memory _voteInfo, bool _voteExecuted, ParachainGovernance.VoteResult _voteResult,) =
            gov.getVoteInfo(_disputeId, 1);
        assertEq(_voteInfo[0], 1); // vote round
        assertEq(_voteInfo[1], _startVote); // start date
        assertEq(_voteInfo[2], block.number); // block number
        assertEq(_voteInfo[3], _startVote + 1 days); // tally date
        assertEq(_voteInfo[4], 0); // tokenholders does support
        assertEq(_voteInfo[5], 0); // tokenholders against
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 0); // users does support
        assertEq(_voteInfo[10], 0); // reporters does support
        assertEq(_voteInfo[13], 0); // team multisig does support
        assertEq(_voteExecuted, false); // vote executed status
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.INVALID)); // vote result

        // Execute vote
        vm.warp(block.timestamp + 3 days);
        gov.executeVote(_disputeId);
        // check vote result and executed status
        (, _voteInfo, _voteExecuted, _voteResult,) = gov.getVoteInfo(_disputeId, 1);
        assertEq(_voteExecuted, true);
        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.INVALID)); // vote result

        // check slashed stake returned to reporter
        assertEq(token.balanceOf(address(bob)), _bobBalance + fakeSlashAmount);
    }

    function testVotingTiesAndPartialParticipation() public {
        // Test scenario where the voting results in a tie
        // Test scenario where not all eligible voters participate in the voting process (multisig doesn't vote)

        // stake for parachain
        uint256 _bobStartBalance = token.balanceOf(address(bob));
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        vm.stopPrank();

        // begin initial dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId, fakeTimestamp, fakeValue, fakeDisputedReporter, fakeDisputeInitiator, fakeSlashAmount
        );

        bytes32 _disputeId = keccak256(abi.encode(fakeParaId, fakeQueryId, fakeTimestamp));

        // VOTE ROUND
        // ensure reporter & random token holder have same voting power (both their votes count as tokenholder votes)
        uint256 _bobBalance = token.balanceOf(address(bob));
        (, uint256 _bobStakedBal, uint256 _bobLockedBal) = staking.getParachainStakerInfo(fakeParaId, bob);
        _bobBalance += _bobStakedBal + _bobLockedBal;
        assertEq(_bobBalance, _bobStartBalance - fakeSlashAmount);
        address marge = address(0xbeef);
        token.mint(address(marge), _bobBalance);
        uint256 _margeBalance = token.balanceOf(address(marge));
        assertEq(_bobBalance, _margeBalance);
        // reporter votes against the dispute
        vm.prank(bob);
        gov.vote(_disputeId, false, true);
        // random token holder votes for the dispute
        vm.prank(marge);
        gov.vote(_disputeId, true, true);
        // skip multisig vote
        vm.prank(paraOwner);
        gov.voteParachain(
            _disputeId,
            200, // _totalTipsFor
            200, // _totalTipsAgainst
            0, // _totalTipsInvalid
            100, // _totalReportsFor
            100, // _totalReportsAgainst
            0 // _totalReportsInvalid
        );
        // tally votes
        vm.warp(block.timestamp + 1 days);
        gov.tallyVotes(_disputeId);

        // check vote state
        (, uint256[16] memory _voteInfo,, ParachainGovernance.VoteResult _voteResult,) =
            gov.getVoteInfo(_disputeId, gov.getVoteRounds(_disputeId));
        assertEq(_voteInfo[4], _margeBalance); // tokenholders does support
        assertEq(_voteInfo[5], _bobBalance); // tokenholders against (bob's stake is slashed and doesn't count towards his vote)
        assertEq(_voteInfo[6], 0); // tokenholders invalid query
        assertEq(_voteInfo[7], 200); // users does support
        assertEq(_voteInfo[8], 200); // users against
        assertEq(_voteInfo[9], 0); // users invalid query
        assertEq(_voteInfo[10], 100); // reports does support
        assertEq(_voteInfo[11], 100); // reports against
        assertEq(_voteInfo[12], 0); // reports invalid query
        assertEq(_voteInfo[13], 0); // team multisig does support
        assertEq(_voteInfo[14], 0); // team multisig against
        assertEq(_voteInfo[15], 0); // team multisig invalid query

        assertEq(uint8(_voteResult), uint8(ParachainGovernance.VoteResult.INVALID)); // vote result
        console.log("vote #1 result: ", uint8(_voteResult));
    }
}
