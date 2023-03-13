// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import "../src/ParachainStaking.sol";
import "../src/ParachainGovernance.sol";


contract TestToken is ERC20 {
    constructor(uint256 initialSupply) ERC20("TestToken", "TT", 18) {
        // _mint(msg.sender, initialSupply);
    }
    function mint(address to, uint256 amount) external virtual {
        _mint(to, amount);
    }
}

contract ParachainStakingTest is Test {
    TestToken public token;
    ParachainRegistry public registry;
    ParachainStaking public staking;
    ParachainGovernance public gov;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);
    address public fakeTeamMultiSig = address(0x3333);
    address public bob = address(0x4444);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 20;

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
    }

    function testConstructor() public {
        assertEq(address(gov.owner()), address(this));
        assertEq(address(gov.parachainStaking()), address(staking));
        assertEq(address(gov.token()), address(token));
    }

    function testBeginParachainDispute() public {
        // create fake dispute initiation inputs
        bytes32 fakeQueryId = keccak256("blah");
        uint256 fakeTimestamp = 1234;
        bytes memory fakeValue = bytes("value");
        address fakeDisputedReporter = address(0x1);
        address fakeDisputeInitiator = address(0x2);
        uint256 fakeDisputeFee = 1234;
        uint256 fakeSlashAmount = 1234;

        // Check that only the owner can call beginParachainDispute
        vm.startPrank(bob);
        vm.expectRevert("not owner");
        gov.beginParachainDispute(
            fakeQueryId,
            fakeTimestamp,
            fakeValue,
            fakeDisputedReporter,
            fakeDisputeInitiator,
            fakeDisputeFee,
            fakeSlashAmount
        );
        vm.stopPrank();

        // successful call
        // vm.startPrank(paraOwner);
        // gov.beginParachainDispute(
        //     fakeQueryId,
        //     fakeTimestamp,
        //     fakeValue,
        //     fakeDisputedReporter,
        //     fakeDisputeInitiator,
        //     fakeDisputeFee,
        //     fakeSlashAmount
        // );
        // vm.stopPrank();
        
    }

    function testVote() public {
    }

    function testVoteParachain() public {
    }

    function testTallyVotes() public {
    }

    function testExecuteVote() public {
    }
}
