// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "./helpers/TestToken.sol";

import "../src/ParachainRegistry.sol";
import { StubXcmUtils } from "./helpers/StubXcmUtils.sol";

contract ParachainRegistryTest is Test {
    TestToken public token;
    ParachainRegistry public registry;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 20;

    XcmTransactorV2 private constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;
    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();

        vm.prank(paraOwner);
        registry.fakeRegister(fakeParaId, fakePalletInstance);

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
        deployPrecompile("StubXcmUtils.sol", XCM_UTILS_ADDRESS);
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

    function testRegister() public {
        // setup
        uint32 fakeParaId2 = 13;
        uint8 fakePalletInstance2 = 9;
        uint256 fakeStakeAmount2 = 50;
        address paraOwner2 = address(0x3333);
        address nonParaOwner = address(0x4444);
        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId2, fakePalletInstance2, paraOwner2);
        
        // test non owner trying to register
        vm.prank(nonParaOwner);
        vm.expectRevert("Not owner");
        registry.register(fakeParaId2, fakePalletInstance2, fakeStakeAmount2);

        // successful register
        vm.prank(paraOwner2);
        registry.register(fakeParaId2, fakePalletInstance2, fakeStakeAmount2);

        // check storage
        ParachainRegistry.Parachain memory parachain = registry.getByAddress(paraOwner2);
        assertEq(parachain.id, fakeParaId2);
        assertEq(parachain.owner, paraOwner2);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance2));
        assertEq(parachain.stakeAmount, fakeStakeAmount2);

        // indirectly check that paraOwner was saved to 'owners' mapping
        parachain = registry.getById(fakeParaId2);
        assertEq(parachain.id, fakeParaId2);
        assertEq(parachain.owner, paraOwner2);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance2));
        assertEq(parachain.stakeAmount, fakeStakeAmount2);
    }

    function testDeregister() public {}

    function testGetById() public {
        ParachainRegistry.Parachain memory parachain = registry.getById(fakeParaId);
        assertEq(parachain.id, fakeParaId);
        assertEq(parachain.owner, paraOwner);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance));
        assertEq(parachain.stakeAmount, fakeStakeAmount);
    }

    function testGetByAddress() public {
        ParachainRegistry.Parachain memory parachain = registry.getByAddress(paraOwner);
        assertEq(parachain.id, fakeParaId);
        assertEq(parachain.owner, paraOwner);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance));
        assertEq(parachain.stakeAmount, fakeStakeAmount);
    }

    function testParachain() public {
        // indirect testing through 'x2' function since 'parachain' is private
        bytes[] memory interior = registry.x2(fakeParaId, fakePalletInstance);
        bytes memory expected = abi.encodePacked(hex"00", abi.encodePacked(fakeParaId));
        assertEq(interior[0], expected);
    }

    function testPallet() public {
        // indirect testing through 'x2' function since 'pallet' is private
        bytes[] memory interior = registry.x2(fakeParaId, fakePalletInstance);
        bytes memory expected = abi.encodePacked(hex"04", abi.encodePacked(fakePalletInstance));
        assertEq(interior[1], expected);
    }

    function testX2() public {
        bytes[] memory interior = registry.x2(fakeParaId, fakePalletInstance);
        bytes memory expected = abi.encodePacked(hex"00", abi.encodePacked(fakeParaId));
        assertEq(interior[0], expected);
        expected = abi.encodePacked(hex"04", abi.encodePacked(fakePalletInstance));
        assertEq(interior[1], expected);
    }
}
