// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";
import "../lib/moonbeam/precompiles/XcmUtils.sol";

// error NotAllowed();
// error NotOwner();
// error ParachainNotRegistered();

interface IRegistry {
    struct Parachain {
        uint32 id;
        address owner;
        bytes palletInstance;
        uint256 weightToFee;
        XcmTransactorV2.Multilocation feeLocation;
    }

    //    todo: suggestion to replace these with simpler below functions, so state only read once per outer calling function
    //    todo: confirm that using struct via memory does indeed pass by reference for internal functions
    //    function owner(uint32 _paraId) external view returns(address);
    //    function palletInstance(uint32 _paraId) external view returns(bytes memory);
    //    function stakeAmount(uint32 _paraId) external view returns(uint256);

    function getById(uint32 _id) external view returns (Parachain memory);
    function getByAddress(address _address) external view returns (Parachain memory);
}

contract ParachainRegistry is IRegistry {
    // todo: confirm optimisation for lookups based on parachain owner address over paraId
    mapping(address => Parachain) private registrations;
    mapping(uint32 => address) private owners;

    XcmTransactorV2 private constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;
    XcmUtils private constant xcmUtils = XCM_UTILS_CONTRACT;

    event ParachainRegistered(address caller, uint32 parachain, address owner);

    /// @dev Register parachain, along with index of Tellor pallet within corresponding runtime.
    /// @param _paraId uint32 The parachain identifier.
    /// @param _palletInstance uint8 The index of the Tellor pallet within the parachain's runtime.
    /// @param _weightToFee uint256 The constant multiplier(fee per weight) used to convert weight to fee
    /// @param _feeLocation XcmTransactorV2.Multilocation The location of the currency type of consumer chain.
    function register(
        uint32 _paraId,
        uint8 _palletInstance,
        uint256 _weightToFee,
        XcmTransactorV2.Multilocation memory _feeLocation
    ) external {
        // Ensure sender is on parachain
        address derivativeAddress =
            xcmUtils.multilocationToAddress(XcmUtils.Multilocation(1, x2(_paraId, _palletInstance)));
        // if (msg.sender != derivativeAddress) revert NotOwner();
        require(msg.sender == derivativeAddress, "Not owner");
        // todo: consider effects of changing pallet instance with re-registration
        registrations[msg.sender] =
            Parachain(_paraId, msg.sender, abi.encodePacked(_palletInstance), _weightToFee, _feeLocation);
        owners[_paraId] = msg.sender;
        emit ParachainRegistered(msg.sender, _paraId, msg.sender);
    }

    /// @dev Deregister parachain.
    function deregister() external view {
        // Ensure parachain is registered & sender is parachain owner
        IRegistry.Parachain memory _parachain = registrations[msg.sender];
        require(_parachain.owner == msg.sender && _parachain.owner != address(0x0), "not owner");

        // todo: remove registrations after considering effects on existing stake/disputes etc.
    }

    function getById(uint32 _id) external view override returns (Parachain memory) {
        // todo: confirm this creates a copy which is then passed around by reference within consuming functions
        return registrations[owners[_id]];
    }

    function getByAddress(address _address) external view override returns (Parachain memory) {
        // todo: confirm this creates a copy which is then passed around by reference within consuming functions
        return registrations[_address];
    }

    function parachain(uint32 _paraId) private pure returns (bytes memory) {
        // 0x00 denotes Parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        // return bytes.concat(hex"00", bytes4(_paraId));
        // TypeError: Member "concat" not found or not visible after argument-dependent lookup in type(bytes storage pointer)
        return abi.encodePacked(hex"00", abi.encodePacked(_paraId));
    }

    function pallet(uint8 _palletInstance) private pure returns (bytes memory) {
        // 0x04 denotes PalletInstance: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        // return bytes.concat(hex"04", bytes1(_palletInstance));
        return abi.encodePacked(hex"04", abi.encodePacked(_palletInstance));
    }

    function x2(uint32 _paraId, uint8 _palletInstance) public pure returns (bytes[] memory) {
        bytes[] memory interior = new bytes[](2);
        interior[0] = parachain(_paraId);
        interior[1] = pallet(_palletInstance);
        return interior;
    }
}
