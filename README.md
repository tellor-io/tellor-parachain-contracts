# Tellor Staking/Governance Contracts for EVM-enabled Parachains
- See the [grant proposal](https://github.com/tellor-io/Grants-Program/blob/master/applications/Tellor.md) for an overview
- See how these contracts interact with oracle consumer parachains via Cross-Consensus Messaging Format (XCM) [here](https://github.com/evilrobot-01/tellor)

## Setup Environment & Run Tests
### Option 1: Run tests using local environment
- [install foundry to local environment](https://github.com/foundry-rs/foundry#installation)
- run the tests: `$ forge test`
### Option 2: Run tests in docker container
- [install docker](https://docs.docker.com/get-docker/)
- build the docker image defined in `Dockerfile` and watch forge build/run the tests within the container: `$ docker build --no-cache --progress=plain .`

### todo
- add basic tests for all functions in `ParachainGovernance.sol`
- use `vm.mockCall` instead of the fake `transactThroughSigned` function. or do what Frank suggests: "That would be a call to a solidity precompile at a specific address on moonbeam. Not sure if you are using foundry, but you might be able to set a fake contract which implements the relevant interface from lib/moonbeam/precompiles at the expected address."
- search for "todo" in code for more
- see PolkaTellor checklist google sheet
- 

### from call w/ Frank
- make parachain contract extendable to include the ability to set fee amounts for xcm calls when each parachain registers
- do benchmarking for xcm calls
- ensure pallet implementation works well w/ contracts side (3/13)
- 
