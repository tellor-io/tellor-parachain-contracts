// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "./helpers/TestToken.sol";

import "../src/ParachainRegistry.sol";


contract ParachainRegistryTest is Test {
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

    function testRegister() public {}

    function testDeregister() public {}

    function testGetById() public {}

    function testGetByAddress() public {}

    function testParachain() public {}

    function testPallet() public {}

    function testX2() public {}
}
