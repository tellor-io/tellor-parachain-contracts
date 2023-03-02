# Tellor Contracts

See https://github.com/evilrobot-01/tellor for overview.

### todo
- finish implementing basic funcs of ParachainGovernance contract

- rmv opendisputesbyid bc that determines dispute fee on consumer chain
- consumer parachain is only calling func like addparachainuservote. this must happen before voting deadline
- either someone on evm chain or oracle consumer chain calls tally/exsecute vote, doesn't matter
- stakers (enabling reporting on consumer chain) must call vote for a dispute id (hash of paraid, queryid, timestamp) before voting deadline


