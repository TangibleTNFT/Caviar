// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

pragma experimental ABIEncoderV2;
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@boringcrypto/boring-solidity/contracts/libraries/BoringMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./interfaces/ICaviarChef.sol";

contract CaviarChefSecondRewarder is OwnableUpgradeable {
    using BoringMath for uint256;
    using BoringMath128 for uint128;
    using SafeERC20 for IERC20;

    IERC20 public rewardToken;

    /// @notice Info of each MCV2 user.
    /// `amount` LP token amount the user has provided.
    /// `rewardDebt` The amount of REWARD entitled to the user.
    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 unpaidRewards;
    }

    /// @notice Info of each MCV2 pool.
    /// `allocPoint` The amount of allocation points assigned to the pool.
    /// Also known as the amount of REWARD to distribute per block.
    struct PoolInfo {
        uint128 accRewardPerShare;
        uint64 lastRewardTime;
    }

    /// @notice Info of each pool.
    PoolInfo public poolInfo;

    /// @notice Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;
    /// @dev Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint;

    uint256 public rewardPerSecond;
    uint256 public ACC_TOKEN_PRECISION;

    address public caviarChef;

    string public __NAME__;

    uint256 internal unlocked;
    modifier lock() {
        require(unlocked == 1, "LOCKED");
        unlocked = 2;
        _;
        unlocked = 1;
    }

    event LogOnReward(address indexed user, uint256 amount, address indexed to);
    event LogUpdatePool(uint64, uint256, uint128);
    event LogRewardPerSecond(uint256 rewardPerSecond);

    constructor() public {}

    function initialize(
        string memory _name,
        IERC20 _rewardToken, 
        uint256 _rewardPerSecond,
        address _caviarChef
    ) public initializer {
        __Ownable_init();
        __NAME__ = _name;
        rewardToken = _rewardToken;
        rewardPerSecond = _rewardPerSecond;
        unlocked = 1;
        ACC_TOKEN_PRECISION = 1e18;
        caviarChef = _caviarChef;
        poolInfo.lastRewardTime = block.timestamp.to64();
    }

    modifier onlyChef() {
        require(msg.sender == caviarChef, "Only Chef can call this function.");
        _;
    }

    function onReward(
        uint256,
        address _user,
        address to,
        uint256,
        uint256 underlying
    ) external onlyChef lock {
        PoolInfo memory pool = updatePool();
        UserInfo storage user = userInfo[_user];
        uint256 pending;
        if (user.amount > 0) {
            pending = 
                (user.amount.mul(pool.accRewardPerShare) / ACC_TOKEN_PRECISION)
                .sub(user.rewardDebt)
                .add(user.unpaidRewards);
            uint256 balance = rewardToken.balanceOf(address(this));
            if (pending > balance) {
                rewardToken.safeTransfer(to, balance);
                user.unpaidRewards = pending - balance;
            } else {
                rewardToken.safeTransfer(to, pending);
                user.unpaidRewards = 0;
            }
        }
        user.amount = underlying;
        user.rewardDebt = underlying.mul(pool.accRewardPerShare) / ACC_TOKEN_PRECISION;
        emit LogOnReward(_user, pending - user.unpaidRewards, to);
    }

    function pendingTokens(
        address user,
        uint256
    ) external view returns (IERC20[] memory rewardTokens, uint256[] memory rewardAmounts) {
        IERC20[] memory _rewardTokens = new IERC20[](1);
        _rewardTokens[0] = (rewardToken);
        uint256[] memory _rewardAmounts = new uint256[](1);
        _rewardAmounts[0] = pendingToken(user);
        return (_rewardTokens, _rewardAmounts);
    }

    /// @notice Sets the reward per second to be distributed. Can only be called by the owner.
    /// @param _rewardPerSecond The amount of Ring to be distributed per second.
    function setRewardPerSecond(uint256 _rewardPerSecond) public onlyOwner {
        rewardPerSecond = _rewardPerSecond;
        emit LogRewardPerSecond(_rewardPerSecond);
    }

    /// @notice Allows owner to reclaim/withdraw any tokens (including reward tokens) held by this contract
    /// @param token Token to reclaim, use 0x00 for Ethereum
    /// @param amount Amount of tokens to reclaim
    /// @param to Receiver of the tokens, first of his name, rightful heir to the lost tokens,
    /// reightful owner of the extra tokens, and ether, protector of mistaken transfers, mother of token reclaimers,
    /// the Khaleesi of the Great Token Sea, the Unburnt, the Breaker of blockchains.
    function reclaimTokens(
        address token,
        uint256 amount,
        address payable to
    ) public onlyOwner {
        if (token == address(0)) {
            to.transfer(amount);
        } else {
            IERC20(token).safeTransfer(to, amount);
        }
    }

    /// @notice View function to see pending Token
    /// @param _user Address of user.
    /// @return pending REWARD reward for a given user.
    function pendingToken(address _user) public view returns (uint256 pending) {
        PoolInfo memory pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        uint256 lpSupply = ICaviarChef(caviarChef).underlying().balanceOf(caviarChef);
        if (block.timestamp > pool.lastRewardTime && lpSupply != 0) {
            uint256 time = block.timestamp.sub(pool.lastRewardTime);
            uint256 _reward = time.mul(rewardPerSecond);
            accRewardPerShare = accRewardPerShare.add(_reward.mul(ACC_TOKEN_PRECISION) / lpSupply);
        }
        pending = 
            (user.amount.mul(accRewardPerShare) / ACC_TOKEN_PRECISION)
            .sub(user.rewardDebt)
            .add(user.unpaidRewards);
    }

    /// @notice Update reward variables of the given pool.
    /// @return pool Returns the pool that was updated.
    function updatePool() public returns (PoolInfo memory pool) {
        pool = poolInfo;
        if (block.timestamp > pool.lastRewardTime) {
            uint256 lpSupply = ICaviarChef(caviarChef).underlying().balanceOf(caviarChef);

            if (lpSupply > 0) {
                uint256 time = block.timestamp.sub(pool.lastRewardTime);
                uint256 _reward = time.mul(rewardPerSecond);
                pool.accRewardPerShare = 
                    pool.accRewardPerShare
                    .add((_reward.mul(ACC_TOKEN_PRECISION) / lpSupply).to128());
            }
            pool.lastRewardTime = block.timestamp.to64();
            poolInfo = pool;
            emit LogUpdatePool(pool.lastRewardTime, lpSupply, pool.accRewardPerShare);
        }
    }
}
