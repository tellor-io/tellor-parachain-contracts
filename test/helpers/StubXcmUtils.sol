// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.3;

import "../../lib/moonbeam/precompiles/XcmUtils.sol";

contract StubXcmUtils {
    // A multilocation is defined by its number of parents and the encoded junctions (interior)
    struct Multilocation {
        uint8 parents;
        bytes[] interior;
    }

    /// Get retrieve the account associated to a given MultiLocation
    /// @custom:selector 343b3e00
    /// @param multilocation The multilocation that we want to know to which account maps to
    /// @return account The account the multilocation maps to in this chain
    function multilocationToAddress(Multilocation memory multilocation)
        external
        view
        returns (address account) 
    {
        return address(0);
    }

    /// Get the weight that a message will consume in our chain
    /// @custom:selector 25d54154
    /// @param message scale encoded xcm mversioned xcm message
    function weightMessage(bytes memory message)
        external
        view
        returns (uint64 weight)
    {
        return uint64(0);
    }

    /// Get units per second charged for a given multilocation
    /// @custom:selector 3f0f65db
    /// @param multilocation scale encoded xcm mversioned xcm message
    function getUnitsPerSecond(Multilocation memory multilocation)
        external
        view
        returns (uint256 unitsPerSecond)
    {
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
}
