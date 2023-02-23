# Tellor Contracts

See https://github.com/evilrobot-01/tellor for overview.

### Notes from call
#### Qs for F:
- Who is the parachain owner, is this decentralized? Or is the owner only ever the pallet that is calling the dispatchable function?
- Can there be multiple oracle pallet instances on one parachain, or something like that, so multiple users on a consumer parachain can have their own Tellor-like oracles to interact with?
- Why mapping account to msg.sender (staker on evm parachain)? Why not automatic?
- Can the registry/parachain contract ever change? Bc we can’t change it in Tellor, so we’d have to redeploy.
- Why is removeParachainValue function in spec for controller contracts? Doesn’t this already happen on oracle consumer chain?

#### Things to check from Nick/Brenda:
- If all the function & storage separate, then why inherit from TellorFlex?
- If you inherit from TellorFlex, make sure that no cross contamination of vars etc. between the old and new functions (like when calling _updateStakeAndPayRewards)
- If you want to use Tellor on the evm compatible parachain, why not just deploy regular tellor there? In the new oracle controller contract, disable all the old functions that shouldn’t be called.
- Oracle consumer chain doesn’t send over dispute id, you create the hash of the para id timestamp and query id to get the dispute id in ParachainGov contract. Then you don’t have to make a bunch of new mappings. Nick says `bytes32 _hash = keccak256(abi.encodePacked(_queryId, _timestamp));` change that <— to include para id , then get rid of all the new parachain mappings you added
- Remove dispute fee transfer and getter function call in new gov contract since handled on the oracle consumer parachain
