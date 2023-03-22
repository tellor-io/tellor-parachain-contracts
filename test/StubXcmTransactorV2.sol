// SPDX-License-Identifier: MIT

pragma solidity ^0.8.3;

import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";

contract StubXcmTransactorV2 is XcmTransactorV2 {
    event TransactThroughSigned(
        Multilocation dest,
        address feeLocationAddress,
        uint64 transactRequiredWeightAtMost,
        bytes call,
        uint256 feeAmount,
        uint64 overallWeight
    );

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
    ) external override {}

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
}
