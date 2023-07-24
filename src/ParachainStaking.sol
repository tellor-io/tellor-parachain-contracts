// SPDX-License-Identifier: MIT

pragma solidity 0.8.3;

import "../lib/moonbeam/precompiles/ERC20.sol";
import {Parachain} from "./Parachain.sol";
import {IRegistry} from "./ParachainRegistry.sol";

interface IParachainStaking {
    function depositParachainStake(uint32 _paraId, bytes calldata _account, uint256 _amount) external;
    function requestParachainStakeWithdrawal(uint32 _paraId, uint256 _amount) external;
    function withdrawParachainStake(uint32 _paraId, address _staker, uint256 _amount) external;
    function slashParachainReporter(uint256 _slashAmount, uint32 _paraId, address _reporter, address _recipient)
        external
        returns (uint256);
    function getTokenAddress() external view returns (address);
    function getParachainStakerInfo(uint32 _paraId, address _staker)
        external
        view
        returns (uint256, uint256, uint256);
    function getParachainStakerDetails(uint32 _paraId, address _staker) external view returns (bytes memory, uint256);
}

/**
 * @author Tellor Inc.
 *  @title ParachainStaking
 *  @dev This contract handles staking and slashing of stakers who enable reporting
 * linked accounts on oracle consumer parachains. This contract is controlled
 * by a single address known as 'governance', which could be an externally owned
 * account or a contract, allowing for a flexible, modular design.
 */
contract ParachainStaking is Parachain {
    // Storage
    IERC20 public token; // token used for staking and rewards
    address public governance; // address with ability to remove values and slash reporters
    address public owner; // contract deployer, can call init function once
    uint256 public totalStakeAmount; // total amount of tokens locked in contract (via stake)
    uint256 public totalStakers; // total number of stakers with at least stakeAmount staked, not exact
    uint256 public toWithdraw; //amountLockedForWithdrawal

    mapping(address => StakeInfo) private stakerDetails; // mapping from a persons address to their staking info
    mapping(uint32 => mapping(address => ParachainStakeInfo)) private parachainStakerDetails;
    mapping(uint32 => mapping(bytes => address)) private paraAccountToAddress; // mapping from a parachain account to a staker address

    // Structs
    struct Report {
        uint256[] timestamps; // array of all newValueTimestamps reported
        mapping(uint256 => uint256) timestampIndex; // mapping of timestamps to respective indices
        mapping(uint256 => uint256) timestampToBlockNum; // mapping of timestamp to block number
        mapping(uint256 => bytes) valueByTimestamp; // mapping of timestamps to values
        mapping(uint256 => address) reporterByTimestamp; // mapping of timestamps to reporters
        mapping(uint256 => bool) isDisputed;
    }

    struct StakeInfo {
        uint256 startDate; // stake or withdrawal request start date
        uint256 stakedBalance; // staked token balance
        uint256 lockedBalance; // amount locked for withdrawal
    }

    struct ParachainStakeInfo {
        StakeInfo _stakeInfo;
        bytes _account;
    }

    // Events
    event NewStaker(address indexed _staker, uint256 indexed _amount);
    event ReporterSlashed(address indexed _reporter, address _recipient, uint256 _slashAmount);
    event StakeWithdrawn(address _staker);
    event StakeWithdrawRequested(address _staker, uint256 _amount);
    event NewParachainStaker(uint32 _paraId, address _staker, bytes _account, uint256 _amount);
    event ParachainReporterSlashed(uint32 _paraId, address _reporter, address _recipient, uint256 _slashAmount);
    event ParachainStakeWithdrawRequested(uint32 _paraId, bytes _account, uint256 _amount);
    event ParachainStakeWithdrawRequestConfirmed(uint32 _paraId, address _staker, uint256 _amount);
    event ParachainStakeWithdrawn(uint32 _paraId, address _staker);

    // Functions
    /**
     * @dev Initializes system parameters
     * @param _registry address of Parachain Registry contract
     * @param _token address of token used for staking and rewards
     */
    constructor(address _registry, address _token) Parachain(_registry) {
        require(_token != address(0), "must set token address");

        token = IERC20(_token);
        owner = msg.sender;
    }

    /**
     * @dev Allows the owner to initialize the ParachainGovernance contract address
     * @param _governanceAddress address of ParachainGovernance contract
     */
    function init(address _governanceAddress) external {
        require(msg.sender == owner, "only owner can set governance address");
        require(governance == address(0), "governance address already set");
        require(_governanceAddress != address(0), "governance address can't be zero address");
        governance = _governanceAddress;
    }

    /// @dev Called by the staker on the EVM compatible parachain that hosts the Tellor controller contracts.
    /// The staker will call this function and pass in the parachain account identifier, which is used to enable
    /// that account to report values over on the oracle consumer parachain.
    /// @param _paraId The parachain ID of the oracle consumer parachain.
    /// @param _account The account identifier of the reporter on the oracle consumer parachain.
    /// @param _amount The amount of tokens to stake.
    function depositParachainStake(uint32 _paraId, bytes calldata _account, uint256 _amount) external {
        require(governance != address(0), "governance address not set");

        // Ensure parachain is registered
        IRegistry.Parachain memory parachain = registry.getById(_paraId);
        require(parachain.owner != address(0x0), "parachain not registered");
        // Ensure account is not linked to another staker
        require(
            paraAccountToAddress[_paraId][_account] == address(0x0)
                || paraAccountToAddress[_paraId][_account] == msg.sender,
            "account already linked to another staker"
        );
        // Ensure staker has enough tokens before editing state
        (,, uint256 _currentLocked) = getParachainStakerInfo(_paraId, msg.sender);
        require(_amount <= token.balanceOf(msg.sender) + _currentLocked, "insufficient balance");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakerDetails[_paraId][msg.sender];
        _parachainStakeInfo._account = _account;
        paraAccountToAddress[_paraId][_account] = msg.sender;

        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        uint256 _lockedBalance = _staker.lockedBalance;
        if (_lockedBalance > 0) {
            if (_lockedBalance >= _amount) {
                // if staker's locked balance covers full _amount, use that
                _staker.lockedBalance -= _amount;
                toWithdraw -= _amount;
            } else {
                // otherwise, stake the whole locked balance and transfer the
                // remaining amount from the staker's address
                require(
                    token.transferFrom(msg.sender, address(this), _amount - _lockedBalance), "transfer case 1 failed"
                );
                toWithdraw -= _staker.lockedBalance;
                _staker.lockedBalance = 0;
            }
        } else {
            require(token.transferFrom(msg.sender, address(this), _amount), "transfer case 2 failed");
        }
        _staker.stakedBalance += _amount;
        _staker.startDate = block.timestamp; // This resets the staker start date to now
        emit NewStaker(msg.sender, _amount);
        emit NewParachainStaker(_paraId, msg.sender, _account, _amount);

        // Call XCM function to notify consumer parachain of new staker
        reportStakeDeposited(parachain, msg.sender, _account, _amount);
    }

    /// @dev Allows a staker on EVM compatible parachain to request withdrawal of their stake for
    /// a specific oracle consumer parachain.
    /// @param _paraId The unique identifier of the oracle consumer parachain.
    /// @param _amount The amount of tokens to withdraw.
    function requestParachainStakeWithdraw(uint32 _paraId, uint256 _amount) external {
        // Ensure parachain is registered
        IRegistry.Parachain memory parachain = registry.getById(_paraId);
        require(parachain.owner != address(0x0), "parachain not registered");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakerDetails[_paraId][msg.sender];
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        require(_staker.stakedBalance >= _amount, "insufficient staked balance");
        _staker.startDate = block.timestamp;
        _staker.stakedBalance -= _amount;
        _staker.lockedBalance += _amount;
        toWithdraw += _amount;
        emit StakeWithdrawRequested(msg.sender, _amount);
        emit ParachainStakeWithdrawRequested(_paraId, _parachainStakeInfo._account, _amount);

        reportStakeWithdrawRequested(parachain, _parachainStakeInfo._account, _amount, msg.sender);
    }

    /// @dev Allows a staker to withdraw their stake.
    /// @param _paraId Identifier of the oracle consumer parachain.
    function withdrawParachainStake(uint32 _paraId) external {
        IRegistry.Parachain memory parachain = registry.getById(_paraId);
        require(parachain.owner != address(0x0), "parachain not registered");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakerDetails[_paraId][msg.sender];
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        require(block.timestamp - _staker.startDate >= 7 days, "lock period not expired");
        require(_staker.lockedBalance > 0, "no locked balance to withdraw");
        uint256 _amount = _staker.lockedBalance;
        require(token.transfer(msg.sender, _amount), "withdraw stake token transfer failed");
        toWithdraw -= _amount;
        _staker.lockedBalance = 0;

        emit StakeWithdrawn(msg.sender);
        emit ParachainStakeWithdrawn(_paraId, msg.sender);

        reportStakeWithdrawn(
            parachain,
            _parachainStakeInfo._account, // staker's linked account on oracle consumer parachain
            _amount
        );
    }

    /**
     * @dev Slashes a reporter and transfers their stake amount to the given recipient
     * Note: this function is only callable by the governance address.
     * @param _paraId is the parachain ID of the oracle consumer parachain
     * @param _reporter is the address of the reporter being slashed
     * @param _recipient is the address receiving the reporter's stake
     * @return _slashAmount uint256 amount of token slashed and sent to recipient address
     */
    function slashParachainReporter(uint256 _slashAmount, uint32 _paraId, address _reporter, address _recipient)
        external
        returns (uint256)
    {
        require(msg.sender == governance, "only governance can slash reporter");
        IRegistry.Parachain memory parachain = registry.getById(_paraId);
        require(parachain.owner != address(0x0), "parachain not registered");

        ParachainStakeInfo storage _parachainStakeInfo = parachainStakerDetails[_paraId][_reporter];
        StakeInfo storage _staker = _parachainStakeInfo._stakeInfo;
        uint256 _stakedBalance = _staker.stakedBalance;
        uint256 _lockedBalance = _staker.lockedBalance;
        if (_lockedBalance >= _slashAmount) {
            // if locked balance is at least _slashAmount, slash from locked balance
            _staker.lockedBalance -= _slashAmount;
            toWithdraw -= _slashAmount;
        } else if (_lockedBalance + _stakedBalance >= _slashAmount) {
            // if locked balance + staked balance is at least _slashAmount,
            // reduce locked balance first, then the remainder from staked balance
            _staker.stakedBalance = _stakedBalance - (_slashAmount - _lockedBalance);
            toWithdraw -= _lockedBalance;
            _staker.lockedBalance = 0;
        } else {
            // if sum(locked balance + staked balance) is less than _slashAmount,
            // slash sum
            _slashAmount = _stakedBalance + _lockedBalance;
            toWithdraw -= _lockedBalance;
            _staker.stakedBalance = 0;
            _staker.lockedBalance = 0;
        }
        if (_slashAmount > 0) {
            require(token.transfer(_recipient, _slashAmount), "transfer failed");
            emit ParachainReporterSlashed(_paraId, _reporter, _recipient, _slashAmount);

            reportSlash(
                parachain,
                _parachainStakeInfo._account, // reporter's account on oracle consumer parachain
                _slashAmount
            );
        }
        return _slashAmount;
    }

    // *****************************************************************************
    // *                                                                           *
    // *                               Getters                                     *
    // *                                                                           *
    // *****************************************************************************

    /**
     * @dev Returns all information about a staker
     * @param _paraId is the parachain ID of the oracle consumer parachain
     * @param _stakerAddress address of staker inquiring about
     * @return uint256 startDate of staking
     * @return uint256 current amount staked
     * @return uint256 current amount locked for withdrawal
     */
    function getParachainStakerInfo(uint32 _paraId, address _stakerAddress)
        public
        view
        returns (uint256, uint256, uint256)
    {
        StakeInfo storage _staker = parachainStakerDetails[_paraId][_stakerAddress]._stakeInfo;
        return (_staker.startDate, _staker.stakedBalance, _staker.lockedBalance);
    }

    /**
     * @dev Returns info relevant to parachain staking
     * @param _paraId is the parachain ID of the oracle consumer parachain
     * @param _stakerAddress address of staker inquiring about
     * @return bytes account on consumer parachain enabled to report by staker
     */
    function getParachainStakerDetails(uint32 _paraId, address _stakerAddress) external view returns (bytes memory) {
        ParachainStakeInfo storage _parachainStakeInfo = parachainStakerDetails[_paraId][_stakerAddress];
        return _parachainStakeInfo._account;
    }

    /**
     * @dev Returns governance address
     * @return address governance
     */
    function getGovernanceAddress() external view returns (address) {
        return governance;
    }

    /**
     * @dev Returns the address of the token used for staking
     * @return address of the token used for staking
     */
    function getTokenAddress() external view returns (address) {
        return address(token);
    }

    /**
     * @dev Returns the address of the contract owner.
     * @return address owner
     */
    function getOwner() external view returns (address) {
        return owner;
    }
}
