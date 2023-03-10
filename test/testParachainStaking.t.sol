// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

// import "../lib/moonbeam/precompiles/ERC20.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import "../src/ParachainStaking.sol";


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

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 20;

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        staking = new ParachainStaking(address(registry), address(token));

        vm.prank(paraOwner);
        registry.fakeRegister(fakeParaId, fakePalletInstance, fakeStakeAmount);
        
        // set fake governance address
        staking.init(address(0x2));

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
        assertEq(address(staking.token()), address(token));
        assertEq(address(staking.registryAddress()), address(registry));
        assertEq(address(staking.governance()), address(0x2));
    }

    function testDepositParachainStake() public {
        // Try to deposit stake with incorrect parachain
        vm.startPrank(paraOwner);
        vm.expectRevert("parachain not registered");
        staking.depositParachainStake(
            uint32(1234),               // _paraId
            bytes("consumerChainAcct"), // _account
            100                         // _amount
        );
        
        // Successfully deposit stake
        assertEq(registry.owner(fakeParaId), paraOwner);
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        assertEq(token.balanceOf(address(paraOwner)), 100);
        staking.depositParachainStake(
            fakeParaId,                 // _paraId
            bytes("consumerChainAcct"), // _account
            20                          // _amount
        );
        assertEq(token.balanceOf(address(paraOwner)), 80);
        assertEq(token.balanceOf(address(staking)), 20);

        vm.stopPrank();
    }

    function testRequestParachainStakeWithdraw() public {
        // Try to request stake withdrawal with incorrect parachain
        vm.startPrank(paraOwner);
        vm.expectRevert("parachain not registered");
        staking.requestParachainStakeWithdraw(
            uint32(1234),               // _paraId
            100                         // _amount
        );

        // Try to request stake that's not deposited
        vm.expectRevert("insufficient staked balance");
        staking.requestParachainStakeWithdraw(
            fakeParaId,                 // _paraId
            100                         // _amount
        );
        
        // Successfully request stake withdrawal
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId,                 // _paraId
            bytes("consumerChainAcct"), // _account
            20                          // _amount
        );
        assertEq(token.balanceOf(address(staking)), 20);
        staking.requestParachainStakeWithdraw(
            fakeParaId,                 // _paraId
            20                          // _amount
        );
        (, , uint256 lockedBalance, , , , , ,) = staking.getParachainStakerInfo(
            fakeParaId,
            paraOwner
        );
        assertEq(lockedBalance, 20);

        vm.stopPrank();
    }

    function testConfirmParachainStakeWithdrawRequest() public {
        // Note: normally, a parachain staker would not be the parachain owner, as
        // functions called by the parachain owner are called via xcm from the consumer
        // chain's pallet; however, for testing they're the same.

        // Deposit stake
        vm.startPrank(paraOwner);
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId,                 // _paraId
            bytes("consumerChainAcct"), // _account
            20                          // _amount
        );

        // Request stake withdrawal
        staking.requestParachainStakeWithdraw(
            fakeParaId,                 // _paraId
            20                          // _amount
        );
        // Check confirmed locked balance
        (, uint256 lockedBalanceConfirmed) = staking.getParachainStakerDetails(
            fakeParaId,
            paraOwner
        );
        assertEq(lockedBalanceConfirmed, 0);

        // Confirm stake withdrawal request
        staking.confirmParachainStakeWithdrawRequest(
            fakeParaId,                 // _paraId
            paraOwner,                   // _staker
            20                          // _amount
        );
        // Check confirmed locked balance
        (, lockedBalanceConfirmed) = staking.getParachainStakerDetails(
            fakeParaId,
            paraOwner
        );
        assertEq(lockedBalanceConfirmed, 20);

        vm.stopPrank();
    }

    function testWithdrawParachainStake() public {
        // Deposit stake
        vm.startPrank(paraOwner);
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId,                 // _paraId
            bytes("consumerChainAcct"), // _account
            20                          // _amount
        );

        // Request stake withdrawal
        staking.requestParachainStakeWithdraw(
            fakeParaId,                 // _paraId
            20                          // _amount
        );

        // Confirm stake withdrawal request
        staking.confirmParachainStakeWithdrawRequest(
            fakeParaId,                 // _paraId
            paraOwner,                   // _staker
            20                          // _amount
        );
        assertEq(token.balanceOf(address(staking)), 20);
        assertEq(token.balanceOf(address(paraOwner)), 80);

        // Try withdraw stake before lock period expires
        vm.expectRevert("lock period not expired");
        staking.withdrawParachainStake(fakeParaId);

        // Wait for lock period to expire (7 days after staker start date)
        vm.warp(block.timestamp + 7 days + 1 seconds);
        // Withdraw stake
        staking.withdrawParachainStake(fakeParaId);
        assertEq(token.balanceOf(address(staking)), 0);
        assertEq(token.balanceOf(address(paraOwner)), 100);

        vm.stopPrank();
    }

    function testSlashParachainReporter() public {
        // Deposit stake
        vm.startPrank(paraOwner);
        token.mint(address(paraOwner), 100);
        token.approve(address(staking), 100);
        staking.depositParachainStake(
            fakeParaId,                 // _paraId
            bytes("consumerChainAcct"), // _account
            20                          // _amount
        );
        assertEq(token.balanceOf(address(staking)), 20);
        vm.stopPrank();

        // Slash stake
        vm.startPrank(staking.governance());
        staking.slashParachainReporter(
            10,                        // _slashAmount
            fakeParaId,                // _paraId
            paraOwner,                 // _reporter
            paraDisputer               // _recipient
        );
        // Check balances
        assertEq(token.balanceOf(address(staking)), 10);
        assertEq(token.balanceOf(address(paraDisputer)), 10);
        vm.stopPrank();
    }
}