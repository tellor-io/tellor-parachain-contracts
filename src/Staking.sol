pragma solidity ^0.8.0;

import "../lib/moonbeam/precompiles/XcmTransactorV2.sol";
import "../lib/moonbeam/precompiles/ERC20.sol";

contract Staking {
    address public owner;
    IERC20 public token;
    mapping(uint32 => ParachainRegistration) public registrations;

    XcmTransactorV2 constant xcmTransactor = XCM_TRANSACTOR_V2_CONTRACT;

    event DepositedStake(address caller, uint32 parachain);
    event DisputeStarted(address caller, uint32 parachain);

    modifier onlyOwner {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    struct ParachainRegistration{
        address owner;
        bytes palletIndex;
        uint256 stakeAmount;
    }

    constructor (address _token) {
        owner = msg.sender;
        token = IERC20(_token);
    }

    error NotOwner();
    error ParachainNotRegistered();
    error InsufficientStakeAmount();

    // Register parachain, along with index of Tellor pallet within corresponding runtime and stake amount
    function register(uint32 _paraId, uint8 _palletIndex, uint256 _stakeAmount) external onlyOwner {
        ParachainRegistration memory registration;
        registration.owner = msg.sender;
        registration.palletIndex = abi.encodePacked(_palletIndex);
        registration.stakeAmount = _stakeAmount;
        registrations[_paraId] = registration;
    }

    // Deposit stake: called by reporter
    function depositStake(uint32 _paraId, uint256 _amount) external {
        if (registrations[_paraId].owner == address(0x0))
            revert ParachainNotRegistered();
        if (_amount < registrations[_paraId].stakeAmount)
            revert InsufficientStakeAmount();

        // todo: Deposit state

        // Notify parachain
        uint64 transactRequiredWeightAtMost = 5000000000;
        bytes memory call = reportStakeToParachain(_paraId, msg.sender, _amount);
        uint256 feeAmount = 10000000000;
        uint64 overallWeight = 9000000000;
        notifyThroughSigned(_paraId, transactRequiredWeightAtMost, call, feeAmount, overallWeight);
        emit DepositedStake(msg.sender, _paraId);
    }

    function beginDispute(uint32 _paraId) external {
        if (registrations[_paraId].owner == address(0x0))
            revert ParachainNotRegistered();

        // todo: dispute

        emit DisputeStarted(msg.sender, _paraId);
    }

//    function requestStakingWithdraw(uint256 _amount) external {
//    }
//
//    function withdrawStake() external {
//    }
//
//    function slashReporter(address _reporter, address _recipient) external {
//
//    }

    function reportStakeToParachain(uint32 _paraId, address _staker, uint256 _amount) private view returns(bytes memory) {
        // Encode call to report(staker, amount) within Tellor pallet
        return bytes.concat(registrations[_paraId].palletIndex, hex"00", bytes20(_staker), bytes32(reverse(_amount)));
    }

    function parachain(uint32 _paraId) private pure returns (bytes memory) {
        // 0x00 denotes parachain: https://docs.moonbeam.network/builders/xcm/xcm-transactor/#building-the-precompile-multilocation
        return bytes.concat(hex"00", bytes4(_paraId));
    }

    function notifyThroughSigned(uint32 _paraId, uint64 _transactRequiredWeightAtMost, bytes memory _call, uint256 _feeAmount, uint64 _overallWeight) private {
        // Create multi-location based on supplied paraId
        XcmTransactorV2.Multilocation memory location;
        location.parents = 1;
        location.interior = new bytes[](1);
        location.interior[0] = parachain(_paraId);

        // Send remote transact
        xcmTransactor.transactThroughSignedMultilocation(location, location, _transactRequiredWeightAtMost, _call, _feeAmount, _overallWeight);
    }

    // https://ethereum.stackexchange.com/questions/83626/how-to-reverse-byte-order-in-uint256-or-bytes32
    function reverse(uint256 input) internal pure returns (uint256 v) {
        v = input;

        // swap bytes
        v = ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8) |
        ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8);

        // swap 2-byte long pairs
        v = ((v & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16) |
        ((v & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16);

        // swap 4-byte long pairs
        v = ((v & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32) |
        ((v & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32);

        // swap 8-byte long pairs
        v = ((v & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64) |
        ((v & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64);

        // swap 16-byte long pairs
        v = (v >> 128) | (v << 128);
    }
}