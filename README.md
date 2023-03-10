# Tellor Staking/Governance Contracts for EVM-enabled Parachains
![Github Actions](https://img.shields.io/github/actions/workflow/status/tellor-io/parity-tellor-contracts/test.yml?label=tests)
[![Discord Chat](https://img.shields.io/discord/461602746336935936)](https://discord.gg/tellor)
[![Twitter Follow](https://img.shields.io/twitter/follow/wearetellor?style=social)](https://twitter.com/WeAreTellor)


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
- add init func to gov contract to initialize parachain staking interface
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

### qs for Nick/Brenda (3/10/23)
- the structure is a bit different than the spec outlined in the grand proposal [here](https://github.com/tellor-io/Grants-Program/blob/master/applications/Tellor.md#project-details), since the oracle functionality is not included in the `ParachainStaking.sol` contract. is this ok?
- 
