pragma solidity ^0.8.0;

// Various helper methods for interfacing with the Tellor pallet on another parachain via XCM
import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";

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

    modifier onlyOwner {
        if (msg.sender != contractOwner) revert NotOwner();
        _;
    }

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
    /// @param _owner address The multi-location derivative account, mapped from the Tellor pallet account on the parachain.
    /// @param _palletIndex uint8 The index of the Tellor pallet within the parachain's runtime.
    /// @param _stakeAmount uint256 The minimum stake amount for the parachain.
    function registerParachain(uint32 _paraId, address _owner, uint8 _palletIndex, uint256 _stakeAmount) external onlyOwner {
        ParachainRegistration memory registration;
        registration.owner = _owner;
        registration.palletIndex = abi.encodePacked(_palletIndex);
        registration.stakeAmount = _stakeAmount;
        registrations[_paraId] = registration;

        emit ParachainRegistered(msg.sender, _paraId, _owner);
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
}