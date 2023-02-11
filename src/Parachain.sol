pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/XcmTransactorV2.sol"; // Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
import { IRegistry, ParachainNotRegistered } from "./ParachainRegistry.sol";

// Helper contract providing cross-chain messaging functionality
abstract contract Parachain {
    IRegistry internal registry; // registry as separate contract to share state between staking and governance contracts

    XcmTransactorV2 private constant xcmTransactor  = XCM_TRANSACTOR_V2_CONTRACT;

    constructor (address _registry) {
        registry = IRegistry(_registry);
    }

    function removeValue(uint32 _paraId, bytes32 _queryId, uint256 _timestamp) internal {
        // Ensure paraId is registered
        if (registry.owner(_paraId) == address(0x0)) revert ParachainNotRegistered();

        // Prepare remote call and send
        // todo: store parameters by call enum, so updateable over time
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = encodeRemoveValue(_paraId, _queryId, _timestamp);
        uint256 feeAmount = 80000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_paraId, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    /// @dev Report stake to a registered parachain.
    /// @param _paraId uint32 The parachain identifier.
    /// @param _staker address The address of the staker.
    /// @param _reporter bytes The corresponding address of the reporter on the parachain.
    /// @param _amount uint256 The staked amount for the parachain.
    function reportStakeDeposited(uint32 _paraId, address _staker, bytes calldata _reporter, uint256 _amount) internal {
        // Ensure paraId is registered
        if (registry.owner(_paraId) == address(0x0)) revert ParachainNotRegistered();

        // Prepare remote call and send
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = encodeReportStakeDeposited(_paraId, _staker, _reporter, _amount);
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_paraId, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    function transactThroughSigned(uint32 _paraId, uint64 _transactRequiredWeightAtMost, bytes memory _call, uint256 _feeAmount, uint64 _overallWeight) private {
        // Create multi-location based on supplied paraId
        XcmTransactorV2.Multilocation memory location;
        location.parents = 1;
        location.interior = new bytes[](1);
        location.interior[0] = parachain(_paraId);

        // Send remote transact
        xcmTransactor.transactThroughSignedMultilocation(location, location, _transactRequiredWeightAtMost, _call, _feeAmount, _overallWeight);
    }

    function encodeRemoveValue(uint32 _paraId, bytes32 _queryId, uint256 _timestamp) private view returns(bytes memory) {
        // Encode call to remove_value(query_id, timestamp) within Tellor pallet
        return bytes.concat(
            registry.palletInstance(_paraId), // pallet index within runtime
            hex"06", // fixed call index within pallet
            _queryId, // identifier of specific data feed
            bytes32(reverse(_timestamp)) // timestamp
        );
    }

    function encodeReportStakeDeposited(uint32 _paraId, address _staker, bytes memory _reporter, uint256 _amount) private view returns(bytes memory) {
        // Encode call to report_stake_deposited(reporter, amount, address) within Tellor pallet
        return bytes.concat(
            registry.palletInstance(_paraId), // pallet index within runtime
            hex"0A", // fixed call index within pallet
            _reporter, // account id of reporter on target parachain
            bytes32(reverse(_amount)), // amount
            bytes20(_staker) // staker
        );
    }

    function parachain(uint32 _paraId) private pure returns (bytes memory) {
        // 0x00 denotes Parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        return bytes.concat(hex"00", bytes4(_paraId));
    }

    // https://ethereum.stackexchange.com/questions/83626/how-to-reverse-byte-order-in-uint256-or-bytes32
    function reverse(uint256 input) internal pure returns (uint256 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
        ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
        ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32) |
        ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);

        // swap 8-byte long pairs
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64) |
        ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);

        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }
}