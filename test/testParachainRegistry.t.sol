// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "./helpers/TestToken.sol";

import "../src/ParachainRegistry.sol";
import "../src/Parachain.sol";
import {StubXcmUtils} from "./helpers/StubXcmUtils.sol";

contract ParachainRegistryTest is Test {
    TestToken public token;
    ParachainRegistry public registry;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeWeightToFee = 5000;

    XcmTransactorV2 private constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;
    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);

    XcmTransactorV2.Multilocation public fakeFeeLocation;

    function parachain(uint32 _paraId) private pure returns (bytes memory) {
        // 0x00 denotes Parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        return abi.encodePacked(hex"00", bytes4(_paraId));
    }

    function x1(uint32 _paraId) public pure returns (bytes[] memory) {
        bytes[] memory interior = new bytes[](1);
        interior[0] = parachain(_paraId);
        return interior;
    }

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        // setting feeLocation as native token of destination chain
        fakeFeeLocation = XcmTransactorV2.Multilocation(1, x1(3));

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
        deployPrecompile("StubXcmUtils.sol", XCM_UTILS_ADDRESS);

        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId, fakePalletInstance, paraOwner);
        vm.prank(paraOwner);
        registry.register(fakeParaId, fakePalletInstance, fakeWeightToFee, fakeFeeLocation);
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
        registry.register(fakeParaId2, fakePalletInstance2, fakeWeightToFee, fakeFeeLocation);

        // successful register
        vm.prank(paraOwner2);
        registry.register(fakeParaId2, fakePalletInstance2, fakeWeightToFee, fakeFeeLocation);

        // check storage
        ParachainRegistry.Parachain memory parachain = registry.getByAddress(paraOwner2);
        assertEq(parachain.id, fakeParaId2);
        assertEq(parachain.owner, paraOwner2);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance2));
        assertEq(parachain.weightToFee, fakeWeightToFee);
        assertEq(parachain.feeLocation.parents, fakeFeeLocation.parents);
        assertEq(parachain.feeLocation.interior[0], fakeFeeLocation.interior[0]);

        // indirectly check that paraOwner was saved to 'owners' mapping
        parachain = registry.getById(fakeParaId2);
        assertEq(parachain.id, fakeParaId2);
        assertEq(parachain.owner, paraOwner2);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance2));
        assertEq(parachain.weightToFee, fakeWeightToFee);
        assertEq(parachain.feeLocation.interior[0], fakeFeeLocation.interior[0]);
    }

    function testDeregister() public {}

    function testGetById() public {
        ParachainRegistry.Parachain memory parachain = registry.getById(fakeParaId);
        assertEq(parachain.id, fakeParaId);
        assertEq(parachain.owner, paraOwner);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance));
    }

    function testGetByAddress() public {
        ParachainRegistry.Parachain memory parachain = registry.getByAddress(paraOwner);
        assertEq(parachain.id, fakeParaId);
        assertEq(parachain.owner, paraOwner);
        assertEq(parachain.palletInstance, abi.encodePacked(fakePalletInstance));
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
