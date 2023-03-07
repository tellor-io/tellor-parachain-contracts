// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../lib/moonbeam/precompiles/ERC20.sol";
// Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";
import "../lib/moonbeam/precompiles/XcmUtils.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import "../src/ParachainStaking.sol";
// import "../src/ParachainGovernance.sol";

abstract contract TestToken is IERC20 {}

contract ParachainStakingTest is Test {
    IERC20 public token;
    address public tokenAddress = address(0x1234);
    ParachainRegistry public registry;
    ParachainStaking public staking;

    address public bob = address(0x1111);

    // XCM setup
    // XcmTransactorV2 private constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;
    // XcmUtils private constant xcmUtils = XCM_UTILS_CONTRACT;
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    // address public derivativeAddressOfParachain = xcmUtils.multilocationToAddress(
    //     XcmUtils.Multilocation(1, x2(fakeParaId, fakePalletInstance)));

    function setUp() public {
        token = IERC20(tokenAddress);
        registry = new ParachainRegistry();
        staking = new ParachainStaking(address(registry), address(token));

        // Register parachain
        // console.log("derivativeAddressOfParachain: %s", derivativeAddressOfParachain);
        // vm.startPrank(derivativeAddressOfParachain);
        // registry.register(
        //     fakeParaId, // _paraId
        //     fakePalletInstance, // _palletInstance
        //     100   // _stakeAmount
        // );
        // vm.stopPrank();
    }

    function testConstructor() public {
        assertEq(address(staking.token()), tokenAddress);
        assertEq(address(staking.registryAddress()), address(registry));
        assertEq(address(staking.governance()), address(0x0));
    }

    function testInit() public {
        staking.init(address(0x1));
        assertEq(address(staking.governance()), address(0x1));
    }

    function testDepositParachainStake() public {
        staking.init(address(0x2));

        // Try to deposit stake with incorrect parachain
        vm.prank(bob);
        vm.expectRevert("parachain not registered");
        staking.depositParachainStake(
            uint32(1234),               // _paraId
            bytes("consumerChainAcct"), // _account
            100                         // _amount
        );
        
        // Deposit stake successfully
    }

}