// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../../lib/moonbeam/precompiles/XcmTransactorV2.sol";

contract StubXcmTransactorV2 is XcmTransactorV2 {
    event TransactThroughSigned(
        Multilocation dest,
        address feeLocationAddress,
        uint64 transactRequiredWeightAtMost,
        bytes call,
        uint256 feeAmount,
        uint64 overallWeight
    );

    TransactThroughSignedCall[] public transactThroughSignedArray;
    TransactThroughSignedMultilocationCall[] public transactThroughSignedMultilocationArray;

    struct TransactThroughSignedCall {
        Multilocation dest;
        address feeLocationAddress;
        uint64 transactRequiredWeightAtMost;
        bytes call;
        uint256 feeAmount;
        uint64 overallWeight;
    }

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
        transactThroughSignedMultilocationArray.push(
            TransactThroughSignedMultilocationCall(
                dest,
                feeLocation,
                transactRequiredWeightAtMost,
                call,
                feeAmount,
                overallWeight
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
        transactThroughSignedArray.push(
            TransactThroughSignedCall(
                dest,
                feeLocationAddress,
                transactRequiredWeightAtMost,
                call,
                feeAmount,
                overallWeight
            )
        );
        emit TransactThroughSigned(
            dest, feeLocationAddress, transactRequiredWeightAtMost, call, feeAmount, overallWeight
            );
    }

    // add this to be excluded from coverage report
    function test() public {}

    function getTransactThroughSignedArray() public view returns(TransactThroughSignedCall[] memory) {
        return transactThroughSignedArray;
    }

    function getTransactThroughSignedMultilocationArray() public view returns(TransactThroughSignedMultilocationCall[] memory) {
        return transactThroughSignedMultilocationArray;
    }
}
