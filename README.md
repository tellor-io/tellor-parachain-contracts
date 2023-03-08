# Tellor Contracts

See https://github.com/evilrobot-01/tellor for overview.

## Setup Environment & Run Tests
### Option 1: Run tests using local environment
- [install foundry to local environment](https://github.com/foundry-rs/foundry#installation)
- run the tests: `$ forge test`
### Option 2: Run tests in docker container
- [install docker](https://docs.docker.com/get-docker/)
- build the docker image defined in `Dockerfile` and watch forge build/run the tests within the container: `$ docker build --no-cache --progress=plain .`

### todo
- add basic tests for all functions in `ParachainGovernance.sol`
- use `vm.mockCall` instead of the fake `transactThroughSigned` function
- or do what Frank suggests: "That would be a call to a solidity precompile at a specific address on moonbeam. Not sure if you are using foundry, but you might be able to set a fake contract which implements the relevant interface from lib/moonbeam/precompiles at the expected address."
- search for "todo" in code for more

### from call w/ Frank
- make parachain contract extendable to include the ability to set fee amounts for xcm calls when each parachain registers
- schedule call w/ Frank to go over his side of the code
- 
