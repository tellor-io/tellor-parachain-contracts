# Tellor Contracts

See https://github.com/evilrobot-01/tellor for overview.

### todo
- fix require statements that check if dispute exists for dispute id
- use the same function signature for gov contract functions that use dispute id. Some take dispute id, others take paraId, queryId, timestamp
- begin tests
- search for "todo" in code for more


### updates for Frank
- add _slashAmount to begin dispute function
- removed all the functions in the evm chain controller contracts that send xcm to remove value on consumer chain, as the value should already be removed on the consumer chain when the dispute is opened
- updating function signatures to take disputeId instead of paraId, queryId, timestamp
- added `updateParachainStakerReportsSubmitted` function to ParachainStaking contract, which needs to be called by the consumer parachain via a reporter over there before they vote on the evm parachain
- 