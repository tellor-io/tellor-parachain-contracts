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

    function setUp() public {
        // to test the github ci action
    }

    function testConstructor() public {
    }

    function testBeginParachainDispute() public {
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
