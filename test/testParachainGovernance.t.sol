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
    address public alice = address(0x5555);
    bytes public bobsFakeAccount = abi.encodePacked(bob, uint256(4444));

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

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
    }

    // From https://book.getfoundry.sh/cheatcodes/get-code#examples
    function deployPrecompile(string memory _contract, address _address) private {
        // Deploy supplied contract
        bytes memory bytecode = abi.encodePacked(vm.getCode(_contract));
        address deployed;
        assembly { deployed := create(0, add(bytecode, 0x20), mload(bytecode)) }
        // Set the bytecode of supplied precompile address
        vm.etch(_address, deployed.code);
    }

    function testConstructor() public {
        assertEq(address(gov.owner()), address(this));
        assertEq(address(gov.parachainStaking()), address(staking));
        assertEq(address(gov.token()), address(token));
    }

    function testBeginParachainDispute() public {
        // create fake dispute initiation inputs
        // bytes32 fakeQueryId = keccak256("blah");
        bytes32 fakeQueryId = keccak256(abi.encode("SpotPrice", abi.encode("btc", "usd")));
        uint256 fakeTimestamp = block.timestamp;
        bytes memory fakeValue = abi.encode(50_000 * 10 ** 8);
        address fakeDisputedReporter = bob;
        address fakeDisputeInitiator = alice;
        uint256 fakeDisputeFee = 10;
        uint256 fakeSlashAmount = 50;

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

        // Fund disputer/disputed
        token.mint(bob, 100);
        token.mint(alice, 100);

        // Reporter deposits stake
        vm.startPrank(bob);
        token.approve(address(staking), 100);
        staking.depositParachainStake(fakeParaId, bobsFakeAccount, 100);
        vm.stopPrank();
        assertEq(token.balanceOf(address(staking)), 100);
        assertEq(token.balanceOf(address(gov)), 0);
        assertEq(token.balanceOf(bob), 0);
        ( , uint256 stakedBalanceBefore, , , , , , , ) = staking.getParachainStakerInfo(
            fakeParaId,
            bob
        );
        assertEq(stakedBalanceBefore, 100);

        // Successfully begin dispute
        vm.startPrank(paraOwner);
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
        // Check reporter was slashed
        (, uint256 _stakedBalance, uint256 _lockedBalance, , , , , , ) = staking.getParachainStakerInfo(
            fakeParaId,
            bob
        );
        assertEq(_stakedBalance, 50);
        assertEq(token.balanceOf(address(staking)), 50);
        assertEq(token.balanceOf(address(gov)), 50);
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
