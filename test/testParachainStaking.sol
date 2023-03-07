// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";

import "../lib/moonbeam/precompiles/ERC20.sol";

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

    function setUp() public {
        token = IERC20(tokenAddress);
        registry = new ParachainRegistry();
        staking = new ParachainStaking(address(registry), address(token));
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



}