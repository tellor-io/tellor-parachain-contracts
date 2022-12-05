# Tellor Contracts

# Deployment
- Compile and start Moonbeam node: https://docs.moonbeam.network/builders/get-started/networks/moonbeam-dev/

- build contracts
    ```
    forge build
    ```
- Deploy token contract
    ```
    forge create --rpc-url http://localhost:9933/ --constructor-args 100 --private-key 0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133 --legacy src/Token.sol:Tribute
    ```

- Deploy staking contract
    ```
    forge create --rpc-url http://localhost:9933/ --constructor-args 0x.... --private-key 0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133 --legacy src/Staking.sol:Staking
    ```
