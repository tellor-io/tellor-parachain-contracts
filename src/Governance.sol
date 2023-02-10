pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { Parachain } from "./Parachain.sol";
import { IRegistry, ParachainRegistry, ParachainNotRegistered, NotOwner } from "./ParachainRegistry.sol";

contract Governance is Parachain  {
    address public owner;

    event DisputeStarted(address caller, uint32 parachain);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor (address _registry) Parachain(_registry) {
        owner = msg.sender;
    }

    function beginParachainDispute(uint32 _paraId) external {
        // Ensure that sender is parachain owner
        address parachainOwner = registry.owner(_paraId);
        if (parachainOwner == address(0x0)) revert ParachainNotRegistered();
        if (msg.sender != parachainOwner) revert NotOwner();

        // todo: dispute

        emit DisputeStarted(msg.sender, _paraId);
    }
}