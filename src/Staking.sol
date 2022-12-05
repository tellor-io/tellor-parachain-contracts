pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/xcm-transactor/src/v2/XcmTransactorV2.sol";
import "../lib/moonbeam/precompiles/assets-erc20/ERC20.sol";

contract Staking {
    IERC20 public token;
    XcmTransactorV2 constant xcmTransactor = XcmTransactorV2(0x000000000000000000000000000000000000080D); // todo: use constructor
    mapping(bytes => XcmTransactorV2.Multilocation) public registrations;

    event Called(address _caller);

    constructor(address _token)
    {
        token = IERC20(_token);
    }

    function call() external {
        emit Called(msg.sender);
    }

    function register(bytes memory _parachain, XcmTransactorV2.Multilocation calldata _location, uint256 _stakeAmount) external {
        registrations[_parachain] = _location;

        // todo: notify parachain?
    }

    function depositStake(bytes memory _parachain, uint256 _amount) external {

        XcmTransactorV2.Multilocation memory location = registrations[_parachain];
        uint64 transactRequiredWeightAtMost;
        bytes memory call;
        uint256 feeAmount;
        uint64 overallWeight;

        // todo: send message to tellor pallet on parachain
        xcmTransactor.transactThroughSigned(location, address(token), transactRequiredWeightAtMost, call, feeAmount, overallWeight);
    }

    function requestStakingWithdraw(uint256 _amount) external {
    }

    function withdrawStake() external {
    }

    function slashReporter(address _reporter, address _recipient) external {

    }
}