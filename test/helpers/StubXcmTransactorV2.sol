// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../lib/moonbeam/precompiles/XcmTransactorV2.sol";

// StubXcmTransactorV2 is a mock of the XcmTransactorV2 precompile used for testing. It should be deployed in
// tests to the real XcmTransactorV2 precompile address so that any calls to the precompile will be forwarded
// to this contract.

contract StubXcmTransactorV2 is XcmTransactorV2 {
    event TransactThroughSigned(
        Multilocation dest,
        address feeLocationAddress,
        uint64 transactRequiredWeightAtMost,
        bytes call,
        uint256 feeAmount,
        uint64 overallWeight
    );

    // Used for for testing, data passed through transactThroughSignedMultilocation is saved here
    TransactThroughSignedMultilocationCall[] public transactThroughSignedMultilocationArray;

    // Struct used for testing transactThroughSignedMultilocation calls
    struct TransactThroughSignedMultilocationCall {
        Multilocation dest;
        Multilocation feeLocation;
        uint64 transactRequiredWeightAtMost;
        bytes call;
        uint256 feeAmount;
        uint64 overallWeight;
    }

    function indexToAccount(uint16 index) external view override returns (address owner) {
        return address(0x0);
    }

    function transactInfoWithSigned(Multilocation memory multilocation)
        external
        view
        override
        returns (uint64 transactExtraWeight, uint64 transactExtraWeightSigned, uint64 maxWeight)
    {
        return (0, 0, 0);
    }

    function feePerSecond(Multilocation memory multilocation) external view override returns (uint256) {
        return 0;
    }

    function transactThroughDerivativeMultilocation(
        uint8 transactor,
        uint16 index,
        Multilocation memory feeAsset,
        uint64 transactRequiredWeightAtMost,
        bytes memory innerCall,
        uint256 feeAmount,
        uint64 overallWeight
    ) external override {}

    function transactThroughDerivative(
        uint8 transactor,
        uint16 index,
        address currencyId,
        uint64 transactRequiredWeightAtMost,
        bytes memory innerCall,
        uint256 feeAmount,
        uint64 overallWeight
    ) external override {}

    function transactThroughSignedMultilocation(
        Multilocation memory dest,
        Multilocation memory feeLocation,
        uint64 transactRequiredWeightAtMost,
        bytes memory call,
        uint256 feeAmount,
        uint64 overallWeight
    ) external override {
        // For testing and verifying correct data passed here, append data to
        // transactThroughSignedMultilocationArray
        transactThroughSignedMultilocationArray.push(
            TransactThroughSignedMultilocationCall(
                dest, feeLocation, transactRequiredWeightAtMost, call, feeAmount, overallWeight
            )
        );
    }

    function transactThroughSigned(
        Multilocation memory dest,
        address feeLocationAddress,
        uint64 transactRequiredWeightAtMost,
        bytes memory call,
        uint256 feeAmount,
        uint64 overallWeight
    ) external override {
        emit TransactThroughSigned(
            dest, feeLocationAddress, transactRequiredWeightAtMost, call, feeAmount, overallWeight
            );
    }

    // add this to be excluded from coverage report. This is a getter for the transactThroughSignedMultilocationArray
    function getTransactThroughSignedMultilocationArray()
        public
        view
        returns (TransactThroughSignedMultilocationCall[] memory)
    {
        return transactThroughSignedMultilocationArray;
    }

    // exclude contract from coverage report
    function test() public {}
}
