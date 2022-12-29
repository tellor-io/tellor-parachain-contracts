pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/ERC20.sol";
import { ITellor, ParachainNotRegistered } from "./Tellor.sol";

contract Governance  {
    address public owner;
    ITellor private tellor;

    event DisputeStarted(address caller, uint32 parachain);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor (address _tellor) {
        owner = msg.sender;
        tellor = ITellor(_tellor);
    }

    error NotOwner();

    function beginDispute(uint32 _paraId) external {
        if (tellor.owner(_paraId) == address(0x0))
            revert ParachainNotRegistered();

        // todo: dispute

        emit DisputeStarted(msg.sender, _paraId);
    }
}