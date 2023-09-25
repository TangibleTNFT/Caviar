// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import "./interfaces/IPearlGauge.sol";
import "./interfaces/ICaviarChef.sol";
import "./libraries/SignedSafeMath.sol";

contract CaviarChef is OwnableUpgradeable, ReentrancyGuardUpgradeable {
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

    /// @notice Address of the LP token for each MCV2 pool.
    IERC20 public underlying;

    /// @notice Address of the rebase Chef.
    ICaviarChef public rebaseChef;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    uint256 public rewardPerSecond;

    uint256 public distributionPeriod;
    uint256 public lastDistributedTime;

    address public smartWalletChecker; // deprecated
    address public gaugeForLP;

    event Deposit(address indexed user, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 amount, address indexed to);
    event Harvest(address indexed user, uint256 amount);
    event LogUpdatePool(uint256 lastRewardTime, uint256 underlyingSupply, uint256 accRewardPerShare);
    event LogRewardPerSecond(uint256 rewardPerSecond);

    string public __NAME__;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        IERC20 _rewardToken,
        IERC20 _underlying,
        uint256 _distributionPeriod
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __NAME__ = _name;
        rewardToken = _rewardToken;
        distributionPeriod = _distributionPeriod;
        underlying = _underlying;
        lastRewardTime = block.timestamp;
    }

    function setDistributionPeriod(uint256 _distributionPeriod) public onlyOwner {
        distributionPeriod = _distributionPeriod;
    }

    function setRewardToken(address _rewardToken) public onlyOwner {
        require(_rewardToken != address(0), "zero");
        rewardToken = IERC20(_rewardToken);
    }

    function setUnderlyingToken(address _underlying) public onlyOwner {
        require(_underlying != address(0), "zero");
        underlying = IERC20(_underlying);
    }

    function setGaugeForLP(address _gaugeForLP) public onlyOwner {
        require(_gaugeForLP != address(0), "zero");
        gaugeForLP = _gaugeForLP;
    }

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerSecond The amount of Reward to be distributed per second.
    function setRewardPerSecond(uint256 _rewardPerSecond) public onlyOwner {
        rewardPerSecond = _rewardPerSecond;
        emit LogRewardPerSecond(_rewardPerSecond);
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

    function setRebaseChef(address _rebaseChef) public onlyOwner {
        require(_rebaseChef != address(0), "zero");
        rebaseChef = ICaviarChef(_rebaseChef);
    }

    function seedRewards(uint256 _amount) external {
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), _amount);
        if (_amount > 0) {
            _setDistributionRate(_amount);
        }
    }

    function pendingReward(address _user) external view returns (uint256 pending) {
        UserInfo storage user = userInfo[_user];
        uint256 underlyingSupply = underlying.balanceOf(address(this));
        uint256 _accRewardPerShare = accRewardPerShare;
        uint256 time = block.timestamp > lastDistributedTime ? lastDistributedTime : block.timestamp;
        if (time > lastRewardTime) {
            time = time.sub(lastRewardTime);
            uint256 rewardAmount = time.mul(rewardPerSecond);
            _accRewardPerShare = _accRewardPerShare.add(rewardAmount.mul(ACC_REWARD_PRECISION).div(underlyingSupply));
        }
        pending = int256(user.amount.mul(_accRewardPerShare) / ACC_REWARD_PRECISION).sub(user.rewardDebt).toUInt256();
    }

    function _updatePool() internal {
        if (block.timestamp > lastRewardTime) {
            uint256 underlyingSupply = underlying.balanceOf(address(this));
            if (underlyingSupply > 0) {
                uint256 time = block.timestamp > lastDistributedTime ? lastDistributedTime : block.timestamp;
                if (time > lastRewardTime) {
                    time = time.sub(lastRewardTime);
                    uint256 rewardAmount = time.mul(rewardPerSecond);
                    accRewardPerShare = accRewardPerShare.add(rewardAmount.mul(ACC_REWARD_PRECISION).div(underlyingSupply));
                }
            }
            lastRewardTime = block.timestamp;
            emit LogUpdatePool(lastRewardTime, underlyingSupply, accRewardPerShare);
        }
    }

    function deposit(uint256 amount, address to) public nonReentrant {
        _updatePool();
        UserInfo storage user = userInfo[to];

        // Effects
        user.amount = user.amount.add(amount);
        user.rewardDebt = user.rewardDebt.add(int256(amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION));
        underlying.safeTransferFrom(msg.sender, address(this), amount);
        rebaseChef.update(msg.sender, to);

        emit Deposit(msg.sender, amount, to);
    }

    function withdraw(uint256 amount, address to) public nonReentrant {
        _updatePool();
        UserInfo storage user = userInfo[msg.sender];

        // Effects
        user.rewardDebt = user.rewardDebt.sub(int256(amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION));
        user.amount = user.amount.sub(amount);
        underlying.safeTransfer(to, amount);
        rebaseChef.update(msg.sender, to);

        emit Withdraw(msg.sender, amount, to);
    }

    function harvest(address to) public nonReentrant {
        _updatePool();
        UserInfo storage user = userInfo[msg.sender];
        int256 accumulatedReward = int256(user.amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 _pendingReward = accumulatedReward.sub(user.rewardDebt).toUInt256();

        // harvest rebase chef data
        rebaseChef.harvestRebase(msg.sender, to);

        // Effects
        user.rewardDebt = accumulatedReward;
        ERC4626(address(rewardToken)).redeem(_pendingReward, to, address(this));

        emit Harvest(msg.sender, _pendingReward);
    }

    function withdrawAndHarvest(uint256 amount, address to) public nonReentrant {
        _updatePool();
        UserInfo storage user = userInfo[msg.sender];
        require(amount <= user.amount, "Withdraw amount exceeds the deposited amount.");
        int256 accumulatedReward = int256(user.amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION);
        uint256 _pendingReward = accumulatedReward.sub(user.rewardDebt).toUInt256();

        // harvest rebase chef data
        rebaseChef.harvestRebase(msg.sender, to);

        // Effects
        user.rewardDebt = accumulatedReward.sub(int256(amount.mul(accRewardPerShare) / ACC_REWARD_PRECISION));
        user.amount = user.amount.sub(amount);
        ERC4626(address(rewardToken)).redeem(_pendingReward, to, address(this));
        underlying.safeTransfer(to, amount);
        
        rebaseChef.update(msg.sender, to);

        emit Withdraw(msg.sender, amount, to);
        emit Harvest(msg.sender, _pendingReward);
    }

    function setName(string memory _name) external onlyOwner {
        __NAME__ = _name;
    }
}
