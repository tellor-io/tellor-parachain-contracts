pragma solidity ^0.8.0;

// Import OpenZeppelin Contract
import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// This ERC-20 contract mints the specified amount of tokens to the contract creator
contract Tribute is ERC20 {
    constructor(uint256 initialSupply) ERC20("Tellor Tribute", "TRB") {
        _mint(msg.sender, initialSupply);
    }
}
