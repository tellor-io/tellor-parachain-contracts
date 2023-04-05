// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "forge-std/console.sol";
import "solmate/tokens/ERC20.sol";

import "./helpers/TestToken.sol";

import "../src/ParachainRegistry.sol";
import "./helpers/TestParachain.sol";
import "./helpers/StubXcmTransactorV2.sol";

contract ParachainTest is Test {
    TestToken public token;
    ParachainRegistry public registry;
    TestParachain public parachain;

    address public paraOwner = address(0x1111);
    address public paraDisputer = address(0x2222);
    address public fakeStakingContract = address(0x9999);
    address fakeStaker = address(0xabcd);
    bytes fakeReporter = abi.encode(fakeStaker);

    // Parachain registration
    uint32 public fakeParaId = 12;
    uint8 public fakePalletInstance = 8;
    uint256 public fakeStakeAmount = 20;

    StubXcmTransactorV2 private constant xcmTransactor = StubXcmTransactorV2(XCM_TRANSACTOR_V2_ADDRESS);

    function setUp() public {
        token = new TestToken(1_000_000 * 10 ** 18);
        registry = new ParachainRegistry();
        parachain = new TestParachain(address(registry));

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

    function testConstructor() public {
        assertEq(address(registry), parachain.registryAddress());
    }

    function testReportStakeDeposited() public {
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            stakeAmount: fakeStakeAmount
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            stakeAmount: fakeStakeAmount
        });
        uint256 fakeAmount = 100e18;

        // test non-registered parachain - should revert with "Parachain not registered"
        vm.expectRevert();
        vm.prank(fakeStakingContract);
        parachain.reportStakeDepositedExternal(badFakeParachain, fakeStaker, fakeReporter, fakeAmount);
        
        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeDepositedExternal(fakeParachain, fakeStaker, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray = xcmTransactor.getTransactThroughSignedMultilocationArray();
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
            hex"09",
            fakeReporter,
            bytes32(parachain.reverseExternal(fakeAmount)),
            bytes20(fakeStaker)
        );
        assertEq(savedData.call, call);
        assertEq(savedData.feeAmount, 10000000000);
        assertEq(savedData.overallWeight, 9000000000);
    }

    function testReportStakeWithdrawRequested() public {
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            stakeAmount: fakeStakeAmount
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            stakeAmount: fakeStakeAmount
        });
        
        uint256 fakeAmount = 100e18;

        // test non-registered parachain - should revert with "Parachain not registered"
        vm.expectRevert();
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawRequestedExternal(badFakeParachain, fakeReporter, fakeAmount, fakeStaker);

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawRequestedExternal(fakeParachain, fakeReporter, fakeAmount, fakeStaker);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray = xcmTransactor.getTransactThroughSignedMultilocationArray();
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
            hex"0A",
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
            stakeAmount: fakeStakeAmount
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            stakeAmount: fakeStakeAmount
        });
        
        uint256 fakeAmount = 100e18;

        // test non-registered parachain - should revert with "Parachain not registered"
        vm.expectRevert();
        vm.prank(fakeStakingContract);
        parachain.reportSlashExternal(badFakeParachain, fakeStaker, paraDisputer, fakeAmount);

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportSlashExternal(fakeParachain, fakeStaker, paraDisputer, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray = xcmTransactor.getTransactThroughSignedMultilocationArray();
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
            hex"0C",
            fakeStaker,
            paraDisputer,
            bytes32(parachain.reverseExternal(fakeAmount))
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
            stakeAmount: fakeStakeAmount
        });
        IRegistry.Parachain memory badFakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: address(0),
            palletInstance: abi.encode(fakePalletInstance),
            stakeAmount: fakeStakeAmount
        });
        
        uint256 fakeAmount = 100e18;

        // test non-registered parachain - should revert with "Parachain not registered"
        vm.expectRevert();
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawnExternal(badFakeParachain, fakeStaker, fakeReporter, fakeAmount);

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawnExternal(fakeParachain, fakeStaker, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray = xcmTransactor.getTransactThroughSignedMultilocationArray();
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
            hex"0B",
            fakeStaker,
            fakeReporter,
            bytes32(parachain.reverseExternal(fakeAmount))
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
            stakeAmount: fakeStakeAmount
        });
        
        uint256 fakeAmount = 100e18;

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawnExternal(fakeParachain, fakeStaker, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray = xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        assertEq(savedData.feeLocation.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
    }

    // pallet() function is private and isn't used, can we delete?
    function testPallet() public {}

    function testX1() public {
        // since function is private, indirectly test through reportStakeWithdrawnExternal call
        // setup
        IRegistry.Parachain memory fakeParachain = IRegistry.Parachain({
            id: fakeParaId,
            owner: paraOwner,
            palletInstance: abi.encode(fakePalletInstance),
            stakeAmount: fakeStakeAmount
        });
        
        uint256 fakeAmount = 100e18;

        // test registered parachain
        vm.prank(fakeStakingContract);
        parachain.reportStakeWithdrawnExternal(fakeParachain, fakeStaker, fakeReporter, fakeAmount);

        // check saved data passed to StubXcmTransactorV2 through transactThroughSigned
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall[] memory savedDataArray = xcmTransactor.getTransactThroughSignedMultilocationArray();
        StubXcmTransactorV2.TransactThroughSignedMultilocationCall memory savedData = savedDataArray[0];

        assertEq(savedData.feeLocation.interior[0], abi.encodePacked(hex"00", bytes4(fakeParaId)));
    }

    function testReverse() public {
        // how do we test this?
    }

    function testRegistryAddress() public {
        assertEq(parachain.registryAddress(), address(registry));
    }
}
