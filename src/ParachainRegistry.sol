pragma solidity ^0.8.0;

// Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";
import "../lib/moonbeam/precompiles/XcmUtils.sol";

    // error NotAllowed();
    // error NotOwner();
    // error ParachainNotRegistered();

interface IRegistry {
    function owner(uint32 _paraId) external view returns(address);

    function palletInstance(uint32 _paraId) external view returns(bytes memory);

    function stakeAmount(uint32 _paraId) external view returns(uint256);
}

contract ParachainRegistry is IRegistry {
    mapping(uint32 => ParachainRegistration) private registrations;

    XcmTransactorV2 private constant xcmTransactor  = XCM_TRANSACTOR_V2_CONTRACT;
    XcmUtils private constant xcmUtils  = XCM_UTILS_CONTRACT;

    event ParachainRegistered(address caller, uint32 parachain, address owner);

    struct ParachainRegistration{
        address owner;
        bytes palletInstance;
        uint256 stakeAmount;
    }

    modifier onlyParachain(uint32 _paraId, uint8 _palletInstance) {
        // Ensure sender is multilocation-derivative account of pallet on parachain
        address derivativeAddress = xcmUtils.multilocationToAddress(XcmUtils.Multilocation(1, x2(_paraId, _palletInstance)));
        // if (msg.sender != derivativeAddress) revert NotOwner();
        require(msg.sender == derivativeAddress, "Not owner");
        _;
    }

    /// @dev Register parachain, along with index of Tellor pallet within corresponding runtime and stake amount.
    /// @param _paraId uint32 The parachain identifier.
    /// @param _palletInstance uint8 The index of the Tellor pallet within the parachain's runtime.
    /// @param _stakeAmount uint256 The minimum stake amount for the parachain.
    function register(uint32 _paraId, uint8 _palletInstance, uint256 _stakeAmount) external onlyParachain(_paraId, _palletInstance) {
        registrations[_paraId] = ParachainRegistration(msg.sender, abi.encodePacked(_palletInstance), _stakeAmount);
        emit ParachainRegistered(msg.sender, _paraId, msg.sender);
    }

    // Used for testing bc normal register was reverting bc of onlyParachain modifier
    // TODO: remove this
    function fakeRegister(uint32 _paraId, uint8 _palletInstance, uint256 _stakeAmount) external {
        registrations[_paraId] = ParachainRegistration(msg.sender, abi.encodePacked(_palletInstance), _stakeAmount);
        emit ParachainRegistered(msg.sender, _paraId, msg.sender);
    }

    function owner(uint32 _paraId) public override view returns(address) {
        return registrations[_paraId].owner;
    }

    function palletInstance(uint32 _paraId) external override view returns(bytes memory) {
        return registrations[_paraId].palletInstance;
    }

    function stakeAmount(uint32 _paraId) external override view returns(uint256) {
        return registrations[_paraId].stakeAmount;
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