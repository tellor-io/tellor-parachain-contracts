pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";
import "../lib/moonbeam/precompiles/ERC20.sol";

contract Staking {
//    IERC20 public token;
    XcmTransactorV2 constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;
    mapping(bytes => XcmTransactorV2.Multilocation) public registrations;

    event Called(address _caller);
    event DepositedStake(address _caller, bytes parachain);

//    constructor(address _token)
//    {
//        token = IERC20(_token);
//    }

    function call() external {
        emit Called(msg.sender);
    }

    function register(bytes memory _parachain, XcmTransactorV2.Multilocation calldata _location, uint256 _stakeAmount) external {
        registrations[_parachain] = _location;

        // todo: notify parachain?
    }

    function depositStake(bytes calldata _parachain) external {
        // Notify parachain: 0x0000000BB8
        notifyThroughSigned(_parachain);
        emit DepositedStake(msg.sender, _parachain);
    }

    function notifyThroughSigned(bytes memory _parachain) private {
        XcmTransactorV2.Multilocation memory location;
        location.parents = 1;
        location.interior = new bytes[](1);
        location.interior[0] = _parachain;
        uint64 transactRequiredWeightAtMost = 1000000000;
        bytes memory report = hex"2800"; // tellor::report()
        uint256 feeAmount = 50000000000000000;
        uint64 overallWeight = 2000000000;

        // todo: send message to tellor pallet on parachain
        xcmTransactor.transactThroughSignedMultilocation(location, location, transactRequiredWeightAtMost, report, feeAmount, overallWeight);
    }

//
//    function notifyThroughDerivative(bytes memory _parachain) {
//        XcmTransactorV2.Multilocation memory location = registrations[_parachain];
//        uint8 transactor = 0;
//        uint16 index = 0;
//        XcmTransactorV2.Multilocation memory feeAsset = XcmTransactorV2.Multilocation(1, new bytes[](0));
//        uint64 transactWeight = 500;
//        bytes memory transactCall;
//        uint256 feeAmount = 1000;
//        uint64 overallWeight = 1000;
//
//        // todo: send message to tellor pallet on parachain
//        xcmTransactor.transactThroughDerivative(transactor, index, feeAsset, transactWeight, transactCall, feeAmount, overallWeight);
//    }
//
//
//    function notifyThroughDerivativeMultilocation(bytes memory _parachain) {
//        XcmTransactorV2.Multilocation memory location = registrations[_parachain];
//        uint8 transactor = 0;
//        uint16 index = 0;
//        XcmTransactorV2.Multilocation memory feeAsset = XcmTransactorV2.Multilocation(1, new bytes[](0));
//        uint64 transactWeight = 500;
//        bytes memory transactCall;
//        uint256 feeAmount = 1000;
//        uint64 overallWeight = 1000;
//
//        // todo: send message to tellor pallet on parachain
//        xcmTransactor.transactThroughDerivativeMultilocation(transactor, index, feeAsset, transactWeight, transactCall, feeAmount, overallWeight);
//    }



    function requestStakingWithdraw(uint256 _amount) external {
    }

    function withdrawStake() external {
    }

    function slashReporter(address _reporter, address _recipient) external {

    }
}