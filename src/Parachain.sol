pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/XcmTransactorV2.sol"; // Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
// import { IRegistry, ParachainNotRegistered } from "./ParachainRegistry.sol";
import {IRegistry} from "./ParachainRegistry.sol";
import {IParachainGovernance} from "./interfaces/IParachainGovernance.sol";

// Helper contract providing cross-chain messaging functionality
abstract contract Parachain {
    IRegistry internal registry; // registry as separate contract to share state between staking and governance contracts

    XcmTransactorV2 private constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;

    constructor(address _registry) {
        registry = IRegistry(_registry);
    }

    /// @dev Report stake to a registered parachain.
    /// @param _parachain Para The registered parachain.
    /// @param _staker address The address of the staker.
    /// @param _reporter bytes The corresponding address of the reporter on the parachain.
    /// @param _amount uint256 The staked amount for the parachain.
    function reportStakeDeposited(
        IRegistry.Parachain memory _parachain,
        address _staker,
        bytes calldata _reporter,
        uint256 _amount
    ) internal {
        // Prepare remote call and send
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = abi.encodePacked(
            _parachain.palletInstance, // pallet index within parachain runtime
            hex"0C", // fixed call index within pallet: 12
            _reporter, // account id of reporter on target parachain
            bytes32(reverse(_amount)), // amount
            bytes20(_staker) // staker
        );
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_parachain.id, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    /// @dev Report stake withdraw request to a registered parachain.
    /// @param _parachain Para The registered parachain.
    /// @param _account bytes The account identifier on the parachain.
    /// @param _amount uint256 The staked amount for the parachain.
    /// @param _staker address The address of the staker.
    function reportStakeWithdrawRequested(
        IRegistry.Parachain memory _parachain,
        bytes memory _account,
        uint256 _amount,
        address _staker
    ) internal {
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = abi.encodePacked(
            _parachain.palletInstance, // pallet index within parachain runtime
            hex"0D", // fixed call index within pallet: 13
            _account,
            bytes32(reverse(_amount)),
            bytes20(_staker) // staker
        );
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_parachain.id, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    /// @dev Report slash to a registered parachain.
    /// @param _parachain Para The registered parachain.
    /// @param _reporter address The corresponding address of the reporter on the parachain.
    /// @param _recipient address The address of the recipient of the slashed stake.
    /// @param _amount uint256 Amount slashed.
    function reportSlash(IRegistry.Parachain memory _parachain, address _reporter, address _recipient, uint256 _amount)
    internal
    {
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = abi.encodePacked(
            _parachain.palletInstance, // pallet index within parachain runtime
            hex"0F", // fixed call index within pallet: 15
            _reporter, // account id of reporter on target parachain
            _recipient, // recipient
            bytes32(reverse(_amount)) // amount
        );
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_parachain.id, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    /// @dev Report stake withdraw to a registered parachain.
    /// @param _parachain Para The registered parachain.
    /// @param _reporter address Address of staker on EVM compatible chain w/ Tellor controller contracts.
    /// @param _amount uint256 Amount withdrawn.
    function reportStakeWithdrawn(IRegistry.Parachain memory _parachain, address _reporter, uint256 _amount) internal {
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = abi.encodePacked(
            _parachain.palletInstance, // pallet index within runtime
            hex"0E", // fixed call index within pallet: 14
            _reporter, // account id of reporter on target parachain
            bytes32(reverse(_amount)) // amount
        );
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_parachain.id, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    /// @dev Report vote tallied to registered parachain.
    /// @param _parachain Para The registered parachain.
    /// @param _disputeId bytes32 The unique identifier of the dispute.
    /// @param _outcome VoteResult The outcome of the vote.
    function reportVoteTallied(
        IRegistry.Parachain memory _parachain,
        bytes32 _disputeId,
        IParachainGovernance.VoteResult _outcome
    ) internal {
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = abi.encodePacked(
            _parachain.palletInstance, // pallet index within runtime
            hex"10", // fixed call index within pallet: 16
            _disputeId, // dispute id
            uint8(_outcome) // outcome
        );
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_parachain.id, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    /// @dev Report vote executed to a registered parachain.
    /// @param _parachain Para The registered parachain.
    /// @param _disputeId bytes32 The unique identifier of the dispute.
    /// @param _outcome VoteResult The outcome of the vote.
    function reportVoteExecuted(
        IRegistry.Parachain memory _parachain,
        bytes32 _disputeId,
        IParachainGovernance.VoteResult _outcome
    ) internal {
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = abi.encodePacked(
            _parachain.palletInstance, // pallet index within runtime
            hex"11", // fixed call index within pallet: 17
            _disputeId, // dispute id
            uint8(_outcome) // outcome
        );
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        transactThroughSigned(_parachain.id, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    function transactThroughSigned(
        uint32 _paraId,
        uint64 _transactRequiredWeightAtMost,
        bytes memory _call,
        uint256 _feeAmount,
        uint64 _overallWeight
    ) private {
        // Create multi-location based on supplied paraId
        XcmTransactorV2.Multilocation memory location = XcmTransactorV2.Multilocation(1, x1(_paraId));
        // Send remote transact
        xcmTransactor.transactThroughSignedMultilocation(
            location, location, _transactRequiredWeightAtMost, _call, _feeAmount, _overallWeight
        );
    }

    function parachain(uint32 _paraId) private pure returns (bytes memory) {
        // 0x00 denotes Parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        return abi.encodePacked(hex"00", bytes4(_paraId));
    }

    function x1(uint32 _paraId) private pure returns (bytes[] memory) {
        bytes[] memory interior = new bytes[](1);
        interior[0] = parachain(_paraId);
        return interior;
    }

    // https://ethereum.stackexchange.com/questions/83626/how-to-reverse-byte-order-in-uint256-or-bytes32
    function reverse(uint256 input) internal pure returns (uint256 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8)
        | ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16)
        | ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32)
        | ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);

        // swap 8-byte long pairs
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64)
        | ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);

        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }

    function registryAddress() public view returns (address) {
        return address(registry);
    }
}
