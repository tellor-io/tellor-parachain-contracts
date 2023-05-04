// SPDX-License-Identifier: MIT

pragma solidity >=0.8.3;

import "../../lib/moonbeam/precompiles/XcmUtils.sol";

// StubXcmUtils is a mock of the XcmUtils precompile used for testing. It should be deployed in
// tests to the real XcmUtils precompile address so that any calls to the precompile will be
// forwarded to this contract.

contract StubXcmUtils {
    // A multilocation is defined by its number of parents and the encoded junctions (interior)
    struct Multilocation {
        uint8 parents;
        bytes[] interior;
    }

    // For testing, save Multilocation hash => fake pallet Multilocation-derivative address
    mapping(bytes32 => address) public fakeMultilocationToAddressMapping;

    // For testing any function which relies on multilocationToAddress,
    // save Multilocation hash => fake account Multilocation-derivative address
    function fakeSetOwnerMultilocationAddress(uint32 paraId, uint8 palletInstance, address owner) public {
        Multilocation memory multilocation = Multilocation(1, x2(paraId, palletInstance));
        bytes32 hash = keccak256(abi.encode(multilocation));
        fakeMultilocationToAddressMapping[hash] = owner;
    }

    /// Get retrieve the account associated to a given MultiLocation
    /// @custom:selector 343b3e00
    /// @param multilocation The multilocation that we want to know to which account maps to
    /// @return account The account the multilocation maps to in this chain
    function multilocationToAddress(Multilocation memory multilocation) external view returns (address account) {
        bytes32 hash = keccak256(abi.encode(multilocation));
        account = fakeMultilocationToAddressMapping[hash];
    }

    /// Get the weight that a message will consume in our chain
    /// @custom:selector 25d54154
    /// @param message scale encoded xcm mversioned xcm message
    function weightMessage(bytes memory message) external view returns (uint64 weight) {
        return uint64(0);
    }

    /// Get units per second charged for a given multilocation
    /// @custom:selector 3f0f65db
    /// @param multilocation scale encoded xcm mversioned xcm message
    function getUnitsPerSecond(Multilocation memory multilocation) external view returns (uint256 unitsPerSecond) {
        return 0;
    }

    /// Execute custom xcm message
    /// @dev This function CANNOT be called from a smart contract
    /// @custom:selector 34334a02
    /// @param message The versioned message to be executed scale encoded
    /// @param maxWeight The maximum weight to be consumed
    function xcmExecute(bytes memory message, uint64 maxWeight) external {
        revert("StubXcmUtils: xcmExecute not implemented");
    }

    /// Send custom xcm message
    /// @custom:selector 98600e64
    /// @param dest The destination chain to which send this message
    /// @param message The versioned message to be sent scale-encoded
    function xcmSend(Multilocation memory dest, bytes memory message) external {
        revert("StubXcmUtils: xcmSend not implemented");
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

    // exclude contract from coverage report
    function test() public {}
}
