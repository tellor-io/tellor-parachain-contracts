# Tellor Contracts

See https://github.com/evilrobot-01/tellor for overview.

### todo
- fix require statements that check if dispute exists for dispute id
- begin tests
- search for "todo" in code for more

- make parachain contract extendable to include the ability to set fee amounts for xcm calls when each parachain registers
- schedule call w/ Frank to go over his side of the code
- 


### updates for Frank
- `voteParachain` expects the reporters' votes to be included in `_vote` array following the users' votes
- all gov functions take `_disputeId` instead of paraId, queryId, and timestamp