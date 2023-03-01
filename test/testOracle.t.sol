// // SPDX-License-Identifier: UNLICENSED
// pragma solidity ^0.8.13;

// import "forge-std/Test.sol";
// import "forge-std/Vm.sol";
// import "forge-std/console.sol";

// import "../src/Oracle.sol";
// import "lib/usingTellor/TellorPlayground.sol";

// contract OracleTest is Test {
//     /*
//     let tellor;
//     let governance;
//     let govSigner;
//     let token;
//     let accounts;
//     let owner;
//     */
//     TellorPlayground public token;
//     Oracle public oracle;
//     address public PARACHAIN = address(0x1111);
//     uint256 public REPORTING_LOCK = 43200;
//     uint256 public STAKE_AMOUNT_DOLLAR_TARGET = 500;
//     uint256 public STAKING_TOKEN_PRICE = 50;
//     uint256 public MINIMUM_STAKE_AMOUNT = 100;
//     uint256 public REWARD_RATE_TARGET = 60 * 60 * 24 * 30; // 30 days
//     bytes public STAKING_TOKEN_PRICE_QUERY_DATA = abi.encode("SpotPrice", abi.encode("trb", "usd"));
//     bytes32 public STAKING_TOKEN_PRICE_QUERY_ID = keccak256(STAKING_TOKEN_PRICE_QUERY_DATA);
//     bytes public ETH_PRICE_QUERY_DATA = abi.encode("SpotPrice", abi.encode("eth", "usd"));
//     bytes32 public ETH_PRICE_QUERY_ID = keccak256(ETH_PRICE_QUERY_DATA);

//     function setUp() public {
//         token = new TellorPlayground();
//         oracle = new Oracle(
//             address(token),
//             REPORTING_LOCK,
//             STAKE_AMOUNT_DOLLAR_TARGET,
//             STAKING_TOKEN_PRICE,
//             MINIMUM_STAKE_AMOUNT,
//             STAKING_TOKEN_PRICE_QUERY_ID
//         );
//     }
// }