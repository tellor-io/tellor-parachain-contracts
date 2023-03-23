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

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 20;

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();

        vm.prank(paraOwner);
        registry.fakeRegister(fakeParaId, fakePalletInstance, fakeStakeAmount);

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
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

    function test5() public {
        // staked and multiple times disputed on one consumer parachain but keeps reporting on that chain
    }

    function test6() public {
        // staked and multiple times disputed across different consumer parachains, but keeps reporting on each
    }

    function test7() public {
        // check updating stake amount (increase/decrease) for different parachains
    }

    function test8() public {
        // check updating stake amount (increase/decrease) for same parachain
    }

    function test9() public {
        // simulate bad value placed, stake withdraw requested, dispute started on oracle consumer parachain
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
