// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "./helpers/TestToken.sol";
import "./helpers/TestParachain.sol";
import {StubXcmUtils} from "./helpers/StubXcmUtils.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import "../src/ParachainStaking.sol";

contract ParachainStakingTest is Test {
    TestToken public token;
    ParachainRegistry public registry;
    ParachainStaking public staking;
    Parachain public parachainContract;
    TestParachain public parachain;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);
    address public bob = address(0x3333);
    address public alice = address(0x4444);
    address public daryl = address(0x5555);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 20;
    uint256 public fakeWeightToFee = 5000;

    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);

    XcmTransactorV2.Multilocation public fakeFeeLocation;

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        vm.startPrank(paraOwner);
        staking = new ParachainStaking(address(registry), address(token));
        parachain = new TestParachain(address(registry));
        // setting feeLocation as native token of destination chain
        fakeFeeLocation = XcmTransactorV2.Multilocation(1, parachain.x1External(3000));
        // set fake governance address
        staking.init(address(0x2));

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
        deployPrecompile("StubXcmUtils.sol", XCM_UTILS_ADDRESS);

        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId, fakePalletInstance, paraOwner);

        registry.register(fakeParaId, fakePalletInstance, fakeWeightToFee, fakeFeeLocation);
        vm.stopPrank();

        // Fund accounts
        token.mint(bob, fakeStakeAmount * 10);
        token.mint(alice, fakeStakeAmount * 10);
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
        assertEq(address(staking.token()), address(token));
        assertEq(address(staking.registryAddress()), address(registry));
        assertEq(address(staking.governance()), address(0x2));
        assertEq(staking.owner(), address(paraOwner));

        // Try to create new w/o passing in token address
        vm.prank(bob);
        vm.expectRevert("must set token address");
        ParachainStaking _ps = new ParachainStaking(address(registry), address(0x0));
    }

    function testInit() public {
        // Try to init as a non-owner
        vm.prank(bob);
        vm.expectRevert("only owner can set governance address");
        staking.init(address(0x3));

        // Call init after already initialized
        console.log("owner: ", staking.getOwner());
        console.log("paraOwner: ", paraOwner);
        vm.prank(paraOwner);
        vm.expectRevert("governance address already set");
        staking.init(address(0x4));

        // Attempt passing in zero address
        ParachainStaking _staking = new ParachainStaking(address(registry), address(token));
        vm.expectRevert("governance address can't be zero address");
        _staking.init(address(0x0));

        // Ensure governance address is set
        assertEq(address(_staking.governance()), address(0));
        _staking.init(address(0x5)); // fake address
        assertEq(address(_staking.governance()), address(0x5));
    }

    function testDepositParachainStake() public {
        // Try when gov address not set
        ParachainStaking _staking = new ParachainStaking(address(registry), address(token));
        vm.prank(bob);
        vm.expectRevert("governance address not set");
        _staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );

        // Try to deposit stake with incorrect parachain
        vm.prank(bob);
        vm.expectRevert("parachain not registered");
        staking.depositParachainStake(
            uint32(1234), // _paraId
            bytes("consumerChainAcct"), // _account
            100 // _amount
        );

        // Successfully deposit stake
        uint256 bobBalance = token.balanceOf(bob);
        assertEq(registry.getById(fakeParaId).owner, paraOwner);
        vm.startPrank(bob);
        token.approve(address(staking), fakeStakeAmount);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );
        vm.stopPrank();
        assertEq(token.balanceOf(address(bob)), bobBalance - fakeStakeAmount);
        assertEq(token.balanceOf(address(staking)), fakeStakeAmount);

        // Try to deposit stake for an account already linked to another staker
        vm.prank(alice);
        vm.expectRevert("account already linked to another staker");
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            fakeStakeAmount // _amount
        );

        // Test depositing with insufficient tokens
        (, uint256 _darylStakedBal, uint256 _darylLockedBal) = staking.getParachainStakerInfo(fakeParaId, daryl);
        console.log("daryl locked balance: ", _darylLockedBal);
        vm.startPrank(daryl);
        vm.expectRevert("insufficient balance");
        staking.depositParachainStake(fakeParaId, bytes("consumerChainAcct2"), 100);
        vm.stopPrank();

        // Deposit more stake
        token.mint(address(bob), 100);
        bobBalance = token.balanceOf(bob);
        vm.startPrank(bob);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            100 // _amount
        );
        vm.stopPrank();
        (, uint256 _bobStaked, uint256 _bobLocked) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_bobStaked, fakeStakeAmount + 100);
        assertEq(_bobLocked, 0);
        assertEq(token.balanceOf(address(staking)), fakeStakeAmount + 100);
        assertEq(token.balanceOf(address(bob)), bobBalance - 100);

        // Deposit more stake when staker has existing locked balance, and amount is more than locked balance
        vm.startPrank(bob);
        (, uint256 _bobStakedBefore, uint256 _bobLockedBefore) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_bobStakedBefore, fakeStakeAmount + 100);
        assertEq(_bobLockedBefore, 0);
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            20 // _amount
        );
        (, uint256 _bobStakedAfter, uint256 _bobLockedAfter) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_bobStakedAfter, _bobStakedBefore - 20);
        assertEq(_bobLockedAfter, 20);
        bobBalance = token.balanceOf(bob);
        uint256 stakingBalance = token.balanceOf(address(staking));
        assertEq(bobBalance, 180);
        console.log("bob balance: ", bobBalance);
        token.approve(address(staking), 80);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            30 // _amount
        );
        vm.stopPrank();
        (, uint256 _bobStakedAfter2, uint256 _bobLockedAfter2) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_bobStakedAfter2, _bobStakedAfter + 30);
        assertEq(_bobLockedAfter2, 0);
        assertEq(token.balanceOf(address(staking)), stakingBalance + 10);
        assertEq(token.balanceOf(address(bob)), bobBalance - 10);

        // Deposit more stake when staker has existing locked balance, and amount is less than locked balance
        vm.startPrank(bob);
        (, _bobStaked, _bobLocked) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_bobLocked, 0);
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            20 // _amount
        );
        (, _bobStakedAfter, _bobLockedAfter) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(_bobStakedAfter, _bobStaked - 20);
        assertEq(_bobLockedAfter, 20);
        bobBalance = token.balanceOf(bob);
        stakingBalance = token.balanceOf(address(staking));
        console.log("bob balance: ", bobBalance);
        (, _bobStaked, _bobLocked) = staking.getParachainStakerInfo(fakeParaId, bob);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            10 // _amount
        );
        vm.stopPrank();
        (, _bobStakedAfter, _bobLockedAfter) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(token.balanceOf(address(bob)), bobBalance);
        assertEq(_bobStaked + 10, _bobStakedAfter);
        assertEq(_bobLockedAfter, 10);
        assertEq(token.balanceOf(address(staking)), stakingBalance);
    }

    function testRequestParachainStakeWithdraw() public {
        // Try to request stake withdrawal with incorrect parachain
        vm.startPrank(paraOwner);
        vm.expectRevert("parachain not registered");
        staking.requestParachainStakeWithdraw(
            uint32(1234), // _paraId
            100 // _amount
        );

        // Try to request stake that's not deposited
        vm.expectRevert("insufficient staked balance");
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            100 // _amount
        );

        // Successfully request stake withdrawal
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            20 // _amount
        );
        assertEq(token.balanceOf(address(staking)), 20);
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            20 // _amount
        );
        (,, uint256 lockedBalance) = staking.getParachainStakerInfo(fakeParaId, paraOwner);
        assertEq(lockedBalance, 20);

        vm.stopPrank();
    }

    function testConfirmParachainStakeWithdrawRequest() public {
        // Note: normally, a parachain staker would not be the parachain owner, as
        // functions called by the parachain owner are called via xcm from the consumer
        // chain's pallet; however, for testing they're the same.

        // Try to confirm stake withdrawal from incorrect sender
        vm.prank(bob);
        vm.expectRevert("not owner");
        staking.confirmParachainStakeWithdrawRequest(
            bob, // _staker
            100 // _amount
        );

        // Deposit stake
        vm.startPrank(paraOwner);
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            20 // _amount
        );

        // Request stake withdrawal
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            20 // _amount
        );
        // Check confirmed locked balance
        (, uint256 lockedBalanceConfirmed) = staking.getParachainStakerDetails(fakeParaId, paraOwner);
        assertEq(lockedBalanceConfirmed, 0);

        // Confirm stake withdrawal request
        staking.confirmParachainStakeWithdrawRequest(
            paraOwner, // _staker
            20 // _amount
        );
        // Check confirmed locked balance
        (, lockedBalanceConfirmed) = staking.getParachainStakerDetails(fakeParaId, paraOwner);
        assertEq(lockedBalanceConfirmed, 20);

        vm.stopPrank();
    }

    function testWithdrawParachainStake() public {
        // Ensure can't withdraw stake from unregistered parachain
        vm.expectRevert("parachain not registered");
        staking.withdrawParachainStake(uint32(1234));

        // Deposit stake
        vm.startPrank(paraOwner);
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            20 // _amount
        );

        // Try withdraw stake before lock period expires
        vm.expectRevert("lock period not expired");
        staking.withdrawParachainStake(fakeParaId);

        // Wait for lock period to expire (7 days after staker start date)
        vm.warp(block.timestamp + 7 days + 1 seconds);

        // No balance to withdraw
        vm.expectRevert("no locked balance to withdraw");
        staking.withdrawParachainStake(fakeParaId);

        // Request stake withdrawal
        staking.requestParachainStakeWithdraw(
            fakeParaId, // _paraId
            20 // _amount
        );

        // Try to withdraw before oracle consumer parachain confirms
        vm.expectRevert("withdraw stake request not confirmed");
        staking.withdrawParachainStake(fakeParaId);

        // Confirm stake withdrawal request
        staking.confirmParachainStakeWithdrawRequest(
            paraOwner, // _staker
            20 // _amount
        );
        assertEq(token.balanceOf(address(staking)), 20);
        assertEq(token.balanceOf(address(paraOwner)), 80);

        // Withdraw stake
        staking.withdrawParachainStake(fakeParaId);
        assertEq(token.balanceOf(address(staking)), 0);
        assertEq(token.balanceOf(address(paraOwner)), 100);

        vm.stopPrank();
    }

    function testSlashParachainReporter() public {
        // Incorrect sender
        vm.prank(bob);
        vm.expectRevert("only governance can slash reporter");
        staking.slashParachainReporter(
            10, // _slashAmount
            fakeParaId, // _paraId
            paraOwner, // _reporter
            paraDisputer // _recipient
        );

        // Unregistered parachain
        vm.prank(staking.governance());
        vm.expectRevert("parachain not registered");
        staking.slashParachainReporter(
            10, // _slashAmount
            uint32(1234), // _paraId
            paraOwner, // _reporter
            paraDisputer // _recipient
        );

        // Slash when zero staked/locked
        vm.prank(staking.governance());
        uint256 _slashAmount = staking.slashParachainReporter(
            10, // _slashAmount
            fakeParaId, // _paraId
            address(0x1234), // _reporter
            paraDisputer // _recipient
        );
        assertEq(_slashAmount, 0);

        // Deposit stake
        vm.startPrank(paraOwner);
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            20 // _amount
        );
        assertEq(token.balanceOf(address(staking)), 20);
        vm.stopPrank();

        // Slash stake
        vm.startPrank(staking.governance());
        staking.slashParachainReporter(
            10, // _slashAmount
            fakeParaId, // _paraId
            paraOwner, // _reporter
            paraDisputer // _recipient
        );
        // Check balances
        assertEq(token.balanceOf(address(staking)), 10);
        assertEq(token.balanceOf(address(paraDisputer)), 10);
        vm.stopPrank();
    }

    function testGetParachainStakerInfo() public {
        // Not a staker
        vm.prank(address(0xbeef));
        (uint256 startDate, uint256 stakedBalance, uint256 lockedBalance) =
            staking.getParachainStakerInfo(fakeParaId, paraOwner);
        assertEq(startDate, 0);
        assertEq(stakedBalance, 0);
        assertEq(lockedBalance, 0);

        // Staker
        vm.startPrank(bob);
        token.mint(address(bob), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            20 // _amount
        );
        (startDate, stakedBalance, lockedBalance) = staking.getParachainStakerInfo(fakeParaId, bob);
        assertEq(startDate, block.timestamp);
        assertEq(stakedBalance, 20);
        assertEq(lockedBalance, 0);
        vm.stopPrank();
    }

    function testGetParachainStakerDetails() public {
        // Not a staker
        vm.prank(address(0xbeef));
        (bytes memory account, uint256 lockedBalanceConfirmed) =
            staking.getParachainStakerDetails(fakeParaId, paraOwner);
        assertEq(account, bytes(""));
        assertEq(lockedBalanceConfirmed, 0);

        // Staker
        vm.startPrank(bob);
        token.mint(address(bob), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId, // _paraId
            bytes("consumerChainAcct"), // _account
            20 // _amount
        );
        (account, lockedBalanceConfirmed) = staking.getParachainStakerDetails(fakeParaId, bob);
        assertEq(account, bytes("consumerChainAcct"));
        assertEq(lockedBalanceConfirmed, 0);
    }

    function testGetGovernanceAddress() public {
        assertEq(staking.getGovernanceAddress(), address(0x2));
    }

    function testGetTokenAddress() public {
        assertEq(staking.getTokenAddress(), address(token));
    }
}
