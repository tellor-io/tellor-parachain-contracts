pragma solidity ^0.8.0;

// Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";
import "../lib/moonbeam/precompiles/XcmUtils.sol";

    error NotAllowed();
    error NotOwner();
    error ParachainNotRegistered();

interface IRegistry {
    function owner(uint32 _paraId) external view returns(address);

    function palletIndex(uint32 _paraId) external view returns(bytes memory);

    function stakeAmount(uint32 _paraId) external view returns(uint256);
}

contract ParachainRegistry is IRegistry {
    address private contractOwner;

    mapping(uint32 => ParachainRegistration) private registrations;

    XcmTransactorV2 private constant xcmTransactor  = XCM_TRANSACTOR_V2_CONTRACT;
    XcmUtils private constant xcmUtils  = XCM_UTILS_CONTRACT;

    event ParachainRegistered(address caller, uint32 parachain, address owner);

    struct ParachainRegistration{
        address owner;
        bytes palletIndex;
        uint256 stakeAmount;
    }

    constructor () {
        contractOwner = msg.sender;
    }

    /// @dev Register parachain, along with index of Tellor pallet within corresponding runtime and stake amount.
    /// @param _paraId uint32 The parachain identifier.
    /// @param _palletIndex uint8 The index of the Tellor pallet within the parachain's runtime.
    /// @param _stakeAmount uint256 The minimum stake amount for the parachain.
    function register(uint32 _paraId, uint8 _palletIndex, uint256 _stakeAmount) external {

        // Ensure sender is derivative account of pallet on parachain
        XcmUtils.Multilocation memory location;
        location.parents = 1;
        location.interior = new bytes[](2);
        location.interior[0] = parachain(_paraId);
        location.interior[1] = pallet(_palletIndex);
        address derivedAddress = xcmUtils.multilocationToAddress(location);
        if (msg.sender != derivedAddress) revert NotOwner();

        ParachainRegistration memory registration;
        registration.owner = msg.sender;
        registration.palletIndex = abi.encodePacked(_palletIndex);
        registration.stakeAmount = _stakeAmount;
        registrations[_paraId] = registration;

        emit ParachainRegistered(msg.sender, _paraId, msg.sender);
    }

    function owner(uint32 _paraId) public view returns(address) {
        return registrations[_paraId].owner;
    }

    function palletIndex(uint32 _paraId) external view returns(bytes memory) {
        return registrations[_paraId].palletIndex;
    }

    function stakeAmount(uint32 _paraId) external view returns(uint256) {
        return registrations[_paraId].stakeAmount;
    }

    function parachain(uint32 _paraId) private pure returns (bytes memory) {
        // 0x00 denotes parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        return bytes.concat(hex"00", bytes4(_paraId));
    }

    function pallet(uint8 _palletIndex) private pure returns (bytes memory) {
        // 0x00 denotes parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        return bytes.concat(hex"04", bytes1(_palletIndex));
    }
}