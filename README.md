# Tellor Contracts

See https://github.com/evilrobot-01/tellor for overview.

### todo
- finish implementing basic funcs of ParachainGovernance contract

- consumer parachain is only calling func like addparachainuservote. this must happen before voting deadline
- either someone on evm chain or oracle consumer chain calls tally/exsecute vote, doesn't matter
- finish `vote` implementation in ParachainGovernance contract
-
- search for "todo" in code for more


### updates for Frank
- update function signature of beginParachainDispute (remove _disputeId, add _slashAmount)
- removed all the functions in the evm chain controller contracts that send xcm to remove value on consumer chain, as the value should already be removed on the consumer chain when the dispute is opened
- removed ParachainValueRemoved event from ParachainGovernance contract
- updated signatures of events to reflect dispute id being determined by paraId, queryId, timestamp. updated signature of voteParachain to reflect this as well
- removed openDisputesById because this is used to determine the disputeFee, but the dispute fee is determined by the consumer chain
- added `updateParachainStakerReportsSubmitted` function to ParachainStaking contract, which needs to be called by the consumer parachain via a reporter over there before they vote on the evm parachain
- 