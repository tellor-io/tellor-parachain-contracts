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

contract ParachainRegistryTest is Test {
    TestToken public token;
    ParachainRegistry public registry;
    TestParachain public parachain;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeWeightToFee = 5000;

    XcmTransactorV2 private constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;
    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);

    XcmTransactorV2.Multilocation public fakeFeeLocation;
    IRegistry.Weights fakeWeights;

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        parachain = new TestParachain(address(registry));
        // setting feeLocation as native token of destination chain
        fakeFeeLocation = XcmTransactorV2.Multilocation(1, parachain.x1External(3000));
        fakeWeights = IRegistry.Weights(1218085000, 1155113000, 261856000, 198884000, 323353000, 1051143000);

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
        deployPrecompile("StubXcmUtils.sol", XCM_UTILS_ADDRESS);

        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId, fakePalletInstance, paraOwner);
        vm.prank(paraOwner);
        registry.register(fakeParaId, fakePalletInstance, fakeWeightToFee, fakeFeeLocation, fakeWeights);
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
        address paraOwner2 = address(0x3333);
        address nonParaOwner = address(0x4444);
        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId2, fakePalletInstance2, paraOwner2);

        // test non owner trying to register
        vm.prank(nonParaOwner);
        vm.expectRevert("Not owner");
        registry.register(fakeParaId, fakePalletInstance, fakeWeightToFee, fakeFeeLocation, fakeWeights);

        // successful register
        vm.prank(paraOwner2);
        registry.register(fakeParaId2, fakePalletInstance2, fakeWeightToFee, fakeFeeLocation, fakeWeights);

        // check storage
        ParachainRegistry.Parachain memory parachainA = registry.getByAddress(paraOwner2);
        assertEq(parachainA.id, fakeParaId2);
        assertEq(parachainA.owner, paraOwner2);
        assertEq(parachainA.palletInstance, abi.encodePacked(fakePalletInstance2));
        assertEq(parachainA.weightToFee, fakeWeightToFee);
        assertEq(parachainA.feeLocation.parents, fakeFeeLocation.parents);
        assertEq(parachainA.feeLocation.interior[0], fakeFeeLocation.interior[0]);

        // indirectly check that paraOwner was saved to 'owners' mapping
        parachainA = registry.getById(fakeParaId2);
        assertEq(parachainA.id, fakeParaId2);
        assertEq(parachainA.owner, paraOwner2);
        assertEq(parachainA.palletInstance, abi.encodePacked(fakePalletInstance2));
        assertEq(parachainA.weightToFee, fakeWeightToFee);
        assertEq(parachainA.feeLocation.interior[0], fakeFeeLocation.interior[0]);
    }

    function testGetById() public {
        ParachainRegistry.Parachain memory parachainB = registry.getById(fakeParaId);
        assertEq(parachainB.id, fakeParaId);
        assertEq(parachainB.owner, paraOwner);
        assertEq(parachainB.palletInstance, abi.encodePacked(fakePalletInstance));
    }

    function testGetByAddress() public {
        ParachainRegistry.Parachain memory parachainC = registry.getByAddress(paraOwner);
        assertEq(parachainC.id, fakeParaId);
        assertEq(parachainC.owner, paraOwner);
        assertEq(parachainC.palletInstance, abi.encodePacked(fakePalletInstance));
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
