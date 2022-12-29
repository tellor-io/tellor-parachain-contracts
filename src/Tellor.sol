pragma solidity ^0.8.0;

// Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";

contract Tellor {
    XcmTransactorV2 private constant xcmTransactor  = XCM_TRANSACTOR_V2_CONTRACT;

    mapping(uint32 => ParachainRegistration) private registrations;

    error ParachainNotRegistered();

    struct ParachainRegistration{
        address owner;
        bytes palletIndex;
        uint256 stakeAmount;
    }

    function owner(uint32 _paraId) internal view returns(address) {
        return registrations[_paraId].owner;
    }

    function stakeAmount(uint32 _paraId) internal view returns(uint256) {
        return registrations[_paraId].stakeAmount;
    }

    // Register parachain, along with index of Tellor pallet within corresponding runtime and stake amount
    function registerParachain(uint32 _paraId, uint8 _palletIndex, uint256 _stakeAmount) internal {
        ParachainRegistration memory registration;
        registration.owner = msg.sender;
        registration.palletIndex = abi.encodePacked(_palletIndex);
        registration.stakeAmount = _stakeAmount;
        registrations[_paraId] = registration;
    }

    function reportStake(uint32 _paraId, address _staker, uint256 _amount) internal {
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = reportStakeToParachain(_paraId, _staker, _amount);
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        notifyThroughSigned(_paraId, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    function notifyThroughSigned(uint32 _paraId, uint64 _transactRequiredWeightAtMost, bytes memory _call, uint256 _feeAmount, uint64 _overallWeight) private {
        // Create multi-location based on supplied paraId
        XcmTransactorV2.Multilocation memory location;
        location.parents = 1;
        location.interior = new bytes[](1);
        location.interior[0] = parachain(_paraId);

        // Send remote transact
        xcmTransactor.transactThroughSignedMultilocation(location, location, _transactRequiredWeightAtMost, _call, _feeAmount, _overallWeight);
    }

    function reportStakeToParachain(uint32 _paraId, address _staker, uint256 _amount) private view returns(bytes memory) {
        // Encode call to report(staker, amount) within Tellor pallet
        return bytes.concat(registrations[_paraId].palletIndex, hex"00", bytes20(_staker), bytes32(reverse(_amount)));
    }

    function parachain(uint32 _paraId) private pure returns (bytes memory) {
        // 0x00 denotes parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
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