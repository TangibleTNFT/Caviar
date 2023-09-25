// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "./interfaces/IPearlGauge.sol";
import "./interfaces/ICaviarChef.sol";
import "./libraries/SignedSafeMath.sol";

contract CaviarRebaseChef is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        int256 rewardDebt;
    }

    uint256 private constant ACC_REWARD_PRECISION = 1e18;

    uint256 public accRewardPerShare;
    uint256 public lastRewardTime;

    /// @notice Address of rewardToken contract.
    IERC20 public rewardToken;

    /// @notice Address of the staking Chef.
    ICaviarChef public stakingChef;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint256 public rewardPerSecond;

    uint256 public distributionPeriod;
    uint256 public lastDistributedTime;

    address public smartWalletChecker;

    uint256 public underlyingTotalSupply;

    event Deposit(address indexed user, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 amount, address indexed to);
    event EmergencyWithdraw(address indexed user, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 lastRewardTime, uint256 underlyingSupply, uint256 accRewardPerShare);
    event LogRewardPerSecond(uint256 rewardPerSecond);

    string public __NAME__;

    modifier stakingChefOnly {
        require(msg.sender == address(stakingChef), "Auth failed");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        IERC20 _rewardToken,
        uint256 _distributionPeriod
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __NAME__ = _name;
        rewardToken = _rewardToken;
        distributionPeriod = _distributionPeriod;
        lastRewardTime = block.timestamp;
    }

    function setDistributionPeriod(uint256 _distributionPeriod) public onlyOwner {
        distributionPeriod = _distributionPeriod;
    }

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerSecond The amount of Reward to be distributed per second.
    function setRewardPerSecond(uint256 _rewardPerSecond) public onlyOwner {
        rewardPerSecond = _rewardPerSecond;
        emit LogRewardPerSecond(_rewardPerSecond);
    }

    function setRewardToken(address _rewardToken) public onlyOwner {
        require(_rewardToken != address(0), "zero");
        rewardToken = IERC20(_rewardToken);
    }

    function _setDistributionRate(uint256 amount) internal {
        _updatePool();
        if (lastDistributedTime > 0 && block.timestamp < lastDistributedTime) {
            uint256 timeLeft = lastDistributedTime.sub(block.timestamp);
            amount = amount.add(rewardPerSecond.mul(timeLeft));
        }
        rewardPerSecond = amount.div(distributionPeriod);
        lastDistributedTime = block.timestamp.add(distributionPeriod);
        _updatePool();
        emit LogRewardPerSecond(rewardPerSecond);
    }

    function setStakingChef(address _stakingChef) public onlyOwner {
        require(_stakingChef != address(0), "zero");
        stakingChef = ICaviarChef(_stakingChef);
    }

    function seedRewards(uint256 _amount) external {
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        if (_amount > 0) {
            _setDistributionRate(_amount);
        }
    }

    function pendingReward(address _user) external view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 time = block.timestamp > lastDistributedTime ? lastDistributedTime : block.timestamp;
        if (time > lastRewardTime) {
            time = time.sub(lastRewardTime);
            uint256 rewardAmount = time.mul(rewardPerSecond);
            _accRewardPerShare = _accRewardPerShare.add(rewardAmount.mul(ACC_REWARD_PRECISION).div(underlyingTotalSupply));
        }
        pending = int256(user.amount.mul(_accRewardPerShare) / ACC_REWARD_PRECISION).sub(user.rewardDebt).toUInt256();
    }

    function _updatePool() internal {
        if (block.timestamp > lastRewardTime) {
            if (underlyingTotalSupply > 0) {
                uint256 time = block.timestamp > lastDistributedTime ? lastDistributedTime : block.timestamp;
                if (time > lastRewardTime) {
                    time = time.sub(lastRewardTime);
                    uint256 rewardAmount = time.mul(rewardPerSecond);
                    accRewardPerShare = accRewardPerShare.add(rewardAmount.mul(ACC_REWARD_PRECISION).div(underlyingTotalSupply));
                }
            }
            lastRewardTime = block.timestamp;
            emit LogUpdatePool(lastRewardTime, underlyingTotalSupply, accRewardPerShare);
        }
    }

    function update(address from, address to) external stakingChefOnly nonReentrant {
        (uint256 staking_amount,) = stakingChef.userInfo(to);
        UserInfo storage user = userInfo[to];
        if (staking_amount > user.amount) {
            uint deposit_amount = staking_amount.sub(user.amount);
            _deposit(deposit_amount, from, to);
        }
        else {
            uint withdraw_amount = user.amount.sub(staking_amount);
            _withdraw(withdraw_amount, from, to);
        }
    }

    function _deposit(uint256 amount, address from, address to) internal {
        _updatePool();
        UserInfo storage user = userInfo[to];

        // Effects
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(int256(amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION));

        // simulate underlying because reward and underlying are the same
        underlyingTotalSupply += amount;
        emit Deposit(from, amount, to);
    }

    function _withdraw(uint256 amount, address from, address to) internal {
        _updatePool();
        UserInfo storage user = userInfo[from];

        // Effects
        user.rewardDebt = user.rewardDebt.sub(int256(amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION));
        user.amount = user.amount.sub(amount);

        // simulate underlying because reward and underlying are the same
        underlyingTotalSupply -= amount;
        emit Withdraw(from, amount, to);
    }

    function harvestRebase(address from, address to) external stakingChefOnly nonReentrant {
        _updatePool();
        UserInfo storage user = userInfo[from];
        int256 accumulatedReward = int256(user.amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 _pendingReward = accumulatedReward.sub(user.rewardDebt).toUInt256();

        // Effects
        user.rewardDebt = accumulatedReward;
        IERC20(rewardToken).safeTransfer(to, _pendingReward);

        emit Harvest(from, _pendingReward);
    }

    function setName(string memory _name) external onlyOwner {
        __NAME__ = _name;
    }
}
