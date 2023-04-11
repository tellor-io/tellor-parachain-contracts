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
- Allocate at least 8GB of RAM to Docker, 3GB swap space, or you'll get out of memory errors
- build the docker image defined in `Dockerfile` and watch forge build/run the tests within the container: `$ docker build --no-cache --progress=plain .`

## Format Code
- `$ forge fmt`
