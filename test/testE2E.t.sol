// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "./helpers/TestToken.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import "../src/ParachainStaking.sol";
import "../src/ParachainGovernance.sol";

contract E2ETests is Test {
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
    uint256 fakeDisputeFee = 10;
    uint256 fakeSlashAmount = 50;

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 100;

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        staking = new ParachainStaking(address(registry), address(token));
        gov = new ParachainGovernance(address(registry), fakeTeamMultiSig);

        vm.prank(paraOwner);
        registry.fakeRegister(fakeParaId, fakePalletInstance, fakeStakeAmount);
        vm.stopPrank();

        gov.init(address(staking));
        staking.init(address(gov));

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);

        // Fund disputer/disputed
        token.mint(bob, fakeStakeAmount * 2);
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

    // function test5() public {
    //     // staked and multiple times disputed on one consumer parachain but keeps reporting on that chain
    // }

    // function test6() public {
    //     // staked and multiple times disputed across different consumer parachains, but keeps reporting on each
    // }

    // function test7() public {
    //     // check updating stake amount (increase/decrease) for different parachains
    // }

    // function test8() public {
    //     // check updating stake amount (increase/decrease) for same parachain
    // }

    function test9() public {
        /*
        simulate bad value placed, stake withdraw requested, dispute started on oracle consumer parachain
        */

        // Stake, then request stake withdrawal
        uint256 initialBalance = token.balanceOf(address(bob));
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            fakeStakeAmount // _amount
        );
        vm.stopPrank();
        (, uint256 stakedBalance, uint256 lockedBalance,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(lockedBalance, fakeStakeAmount);
        assertEq(stakedBalance, fakeStakeAmount);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount);

        // Can assume bad value was submitted on oracle consumer parachain 🪄

        // Dispute
        // Fund dispute initiator w/ fee amount & approve dispute fee transfer
        token.mint(fakeDisputeInitiator, fakeDisputeFee);
        vm.prank(fakeDisputeInitiator);
        token.approve(address(gov), fakeDisputeFee);

        // Successfully begin dispute
        vm.prank(paraOwner);
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            fakeDisputedReporter,
            fakeDisputeInitiator,
            fakeDisputeFee,
            fakeSlashAmount
        );
        // Check reporter was slashed
        (, uint256 _stakedBalAfter, uint256 _lockedBalAfter,,,,,,) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_stakedBalAfter, fakeStakeAmount);
        assertEq(token.balanceOf(address(bob)), initialBalance - fakeStakeAmount);
        assertEq(_lockedBalAfter, fakeStakeAmount - fakeSlashAmount);

        assertEq(token.balanceOf(address(staking)), 50);
        assertEq(token.balanceOf(address(gov)), fakeDisputeFee + fakeSlashAmount);

        // todo: what if the slash amount is more than the stake amount?
        // todo: check if stake amount is supposed to remain the same after requesting withdrawal & slashed from dispute
    }

    function test10() public {
        // simulate bad values places on multiple consumer parachains, stake withdraws requested across each consumer parachain, disputes started across each parachain
    }

    function test11() public {
        // multiple disputes
    }

    function test12() public {
        // multiple disputes, increase stake amount mid dispute
    }

    function test13() public {
        // multiple disputes, decrease stake amount mid dispute
    }

    function test14() public {
        // multiple disputes, changing governance address mid dispute
    }

    function test15() public {
        // no votes on a dispute
    }

    function test16() public {
        // multiple vote rounds on a dispute, all passing
    }

    function test17() public {
        // multiple vote rounds on a dispute, overturn result
    }

    function test18() public {
        // multiple votes from all stakeholders (tokenholders, reporters, users, teamMultisig) (test the handling of edge cases in voting rounds (e.g., voting ties, uneven votes, partial participation))
    }

    function test19() public {
        // test submitting bad identical values (same value, query id, & submission timestamp) on different parachains, disputes open for all, ensure no cross contamination in gov/staking contracts
    }
}
