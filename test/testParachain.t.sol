// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "../src/ParachainRegistry.sol";
import "./helpers/TestParachain.sol";
import "./helpers/TestToken.sol";
import "./helpers/StubXcmTransactorV2.sol";
import {StubXcmUtils} from "./helpers/StubXcmUtils.sol";

contract ParachainTest is Test {
    TestToken public token;
    ParachainRegistry public registry;
    TestParachain public parachain;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);
    address public fakeStakingContract = address(0x9999);
    address fakeStaker = address(0xabcd);
    bytes fakeReporter = abi.encode(fakeStaker); // fake reporter account on oracle consumer parachain
    uint256 fakeWeightToFee = 5000;
    uint8 fakeDecimals = 12;

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;

    StubXcmTransactorV2 private constant xcmTransactor = StubXcmTransactorV2(XCM_TRANSACTOR_V2_ADDRESS);
    StubXcmUtils private constant xcmUtils = StubXcmUtils(XCM_UTILS_ADDRESS);
    XcmTransactorV2.Multilocation fakeFeeLocation;

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        parachain = new TestParachain(address(registry));
        fakeFeeLocation = XcmTransactorV2.Multilocation(0, parachain.x1External(3));

        // Set fake precompile(s)
        deployPrecompile("StubXcmTransactorV2.sol", XCM_TRANSACTOR_V2_ADDRESS);
        deployPrecompile("StubXcmUtils.sol", XCM_UTILS_ADDRESS);

        xcmUtils.fakeSetOwnerMultilocationAddress(fakeParaId, fakePalletInstance, paraOwner);
        vm.prank(paraOwner);

        registry.register(fakeParaId, fakePalletInstance, fakeWeightToFee, fakeDecimals, fakeFeeLocation);
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
        assertEq(address(registry), parachain.registryAddress());
    }

    function testReportStakeDeposited() public {
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });
        uint256 fakeAmount = 100e18;

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeDepositedExternal(fakeParachain, fakeStaker, fakeReporter, fakeAmount);

        // check saved data passed to mock StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray =
            xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        assertEq(savedData.dest.parents, 1);
        assertEq(savedData.dest.interior.length, 1);
        assertEq(savedData.dest.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.feeLocation.parents, 1);
        assertEq(savedData.feeLocation.interior.length, 1);
        assertEq(savedData.feeLocation.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.transactRequiredWeightAtMost, 1218085000);
        bytes memory call = abi.encodePacked(
            abi.encode(fakePalletInstance),
            hex"0C",
            fakeReporter,
            bytes32(parachain.reverseExternal(fakeAmount)),
            bytes20(fakeStaker)
        );
        assertEq(savedData.call, call);
        assertEq(savedData.feeAmount, 2609);
        assertEq(savedData.overallWeight, 5218085000);
    }

    function testReportStakeWithdrawRequested() public {
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });

        uint256 fakeAmount = 100e18;

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawRequestedExternal(fakeParachain, fakeReporter, fakeAmount, fakeStaker);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray =
            xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        assertEq(savedData.dest.parents, 1);
        assertEq(savedData.dest.interior.length, 1);
        assertEq(savedData.dest.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.feeLocation.parents, 1);
        assertEq(savedData.feeLocation.interior.length, 1);
        assertEq(savedData.feeLocation.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.transactRequiredWeightAtMost, 5000000000);
        bytes memory call = abi.encodePacked(
            abi.encode(fakePalletInstance),
            hex"0D",
            fakeReporter,
            bytes32(parachain.reverseExternal(fakeAmount)),
            bytes20(fakeStaker)
        );
        assertEq(savedData.call, call);
        assertEq(savedData.feeAmount, 10000000000);
        assertEq(savedData.overallWeight, 9000000000);
    }

    function testReportSlash() public {
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });

        uint256 fakeAmount = 100e18;

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportSlashExternal(fakeParachain, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray =
            xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        assertEq(savedData.dest.parents, 1);
        assertEq(savedData.dest.interior.length, 1);
        assertEq(savedData.dest.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.feeLocation.parents, 1);
        assertEq(savedData.feeLocation.interior.length, 1);
        assertEq(savedData.feeLocation.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.transactRequiredWeightAtMost, 5000000000);
        bytes memory call = abi.encodePacked(
            abi.encode(fakePalletInstance), hex"0F", fakeReporter, bytes32(parachain.reverseExternal(fakeAmount))
        );
        assertEq(savedData.call, call);
        assertEq(savedData.feeAmount, 10000000000);
        assertEq(savedData.overallWeight, 9000000000);
    }

    function testReportStakeWithdrawn() public {
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });

        uint256 fakeAmount = 100e18;

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawnExternal(fakeParachain, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray =
            xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        assertEq(savedData.dest.parents, 1);
        assertEq(savedData.dest.interior.length, 1);
        assertEq(savedData.dest.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.feeLocation.parents, 1);
        assertEq(savedData.feeLocation.interior.length, 1);
        assertEq(savedData.feeLocation.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
        assertEq(savedData.transactRequiredWeightAtMost, 5000000000);
        bytes memory call = abi.encodePacked(
            abi.encode(fakePalletInstance), hex"0E", fakeReporter, bytes32(parachain.reverseExternal(fakeAmount))
        );
        assertEq(savedData.call, call);
        assertEq(savedData.feeAmount, 10000000000);
        assertEq(savedData.overallWeight, 9000000000);
    }

    function testTransactThroughSigned() public {}

    function testParachain() public {
        // since function is private, indirectly test through reportStakeWithdrawnExternal call
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });

        uint256 fakeAmount = 100e18;
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawnExternal(fakeParachain, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray =
            xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        //assertEq(savedData.feeLocation, fakeFeeLocation);
    }

    function testX1() public {
        // since function is private, indirectly test through reportStakeWithdrawnExternal call
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            weightToFee: fakeWeightToFee,
            decimals: fakeDecimals,
            feeLocation: fakeFeeLocation
        });

        uint256 fakeAmount = 100e18;
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawnExternal(fakeParachain, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray =
            xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        assertEq(savedData.feeLocation.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
    }

    function testReverse() public {
        uint256 reverse1 = 0x0100000000000000000000000000000000000000000000000000000000000000;
        uint256 reverse2 = 0x0200000000000000000000000000000000000000000000000000000000000000;
        uint256 reverse100 = 0x6400000000000000000000000000000000000000000000000000000000000000;
        uint256 reverse1e18 = 0x000064a7b3b6e00d000000000000000000000000000000000000000000000000;

        assertEq(parachain.reverseExternal(0), 0);
        assertEq(parachain.reverseExternal(1), reverse1);
        assertEq(parachain.reverseExternal(2), reverse2);
        assertEq(parachain.reverseExternal(100), reverse100);
        assertEq(parachain.reverseExternal(1e18), reverse1e18);

        assertEq(parachain.reverseExternal(parachain.reverseExternal(0)), 0);
        assertEq(parachain.reverseExternal(parachain.reverseExternal(1)), 1);
        assertEq(parachain.reverseExternal(parachain.reverseExternal(2)), 2);
        assertEq(parachain.reverseExternal(parachain.reverseExternal(100)), 100);
        assertEq(parachain.reverseExternal(parachain.reverseExternal(1e18)), 1e18);
    }

    function testRegistryAddress() public {
        assertEq(parachain.registryAddress(), address(registry));
    }

    function testConvertWeightToFee() public {
        uint256 overallWeight = 500000000;
        uint256 weightToFee = 100000;
        uint8 decimals = 12;

        assertEq(parachain.convertWeightToFeeExternal(overallWeight, weightToFee, decimals), 50);
    }
}
