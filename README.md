# Tellor Contracts
- Uses External XC-20 token (xcTRB), which is a ERC-20 style interface to a Substrate asset. 
- Staking contract initialised with External XC-20 Precompile Address

# Deployment
- Compile and start Moonbeam node: https://docs.moonbeam.network/builders/get-started/networks/moonbeam-dev/
- Create xcTRB asset (Developer, sudo, assets, forceCreate)
- build contracts
    ```
    forge build
    ```

- Deploy staking contract
    ```
    forge create --rpc-url http://localhost:9933/ --constructor-args 0xFFFFFFFFxcTok3nAddr355 --private-key 0x5fb92d6e98884f76de468fa3f6278f8807c48bebc13595d45af5bdc4da702133 --legacy src/Staking.sol:Staking
    ```
