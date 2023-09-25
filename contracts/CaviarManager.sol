// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/ICaviarStrategy.sol";
import "./interfaces/ICaviarChef.sol";
import "./interfaces/ICaviar.sol";
import "./interfaces/IPearlPair.sol";
import "./interfaces/ICaviarFeeManager.sol";
import "./interfaces/IVePearl.sol";

contract CaviarManager is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    string public __NAME__;
    address public pearl;
    uint256 public MAXTIME;
    uint256 public WEEK;
    uint256 public MIN_VE_DEPOSIT_FEE;
    uint256 public MAX_VE_DEPOSIT_FEE;

    address public feeManager;
    address public strategy;
    address public caviar;
    address public vePearl;

    address public pearlPair;

    address public smartWalletWhitelist; // deprecated

    bool public veDepositEnabled;
    bool public isPromotionPeriod;
    uint256 public PROMO_VE_DEPOSIT_FEE;
    uint256 public MULTIPLIER;
    uint256 public REDEEM_FEE;

    uint256 public beginTimestamp;

    uint256 public caviarSupplyAtCurrentEpoch;

    mapping(uint256 => uint256) public mintedFromNftAt;
    mapping(address => bool) public isKeeper;

    bool public redeemEnabled;

    uint256 public vePearlLastBalance;

    event InitialLock(uint256 unlockTime);
    event IncreaseAmount(uint256 amount);
    event SetPromotionPeriod(bool set, uint256 fee);
    event SetBeginTimestamp(uint256 timestamp);
    event Deposit(address indexed sender, uint256 amount);
    event DepositNFT(address indexed sender, uint256 tokenId, uint256 amount);
    event Redeem(address indexed sender, uint256 amount, uint256 redeemed);
    event SetPearl(address pearl);
    event SetPearlPair(address pair);
    event EnableVePearlDeposit();
    event DisableVePearlDeposit();
    event Rebase(uint amount);
    event EmissionsClaimed(uint256 amount);
    event KeeperAdded(address indexed keeper);
    event KeeperRemoved(address indexed keeper);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        address _strategy,
        address _caviar,
        address _pearl,
        address _vePearl,
        address _pearlPair,
        address _feeManager,
        uint _lockingYear // eg.: crv = 4, lqdr = 2
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __NAME__ = _name;
        feeManager = _feeManager;
        strategy = _strategy;

        caviar = _caviar;
        vePearl = _vePearl;

        pearlPair = _pearlPair;

        MAXTIME = _lockingYear * 364 * 86400;
        WEEK = 7 * 86400;
        pearl = _pearl;

        veDepositEnabled = true;
        isPromotionPeriod = false;

        MIN_VE_DEPOSIT_FEE = 125;
        MAX_VE_DEPOSIT_FEE = 700;
        MULTIPLIER = 1000;

        REDEEM_FEE = 35;

        redeemEnabled = true;

        vePearlLastBalance = 0;
    }

    // --- modifiers ---

    modifier onlyOwnerOrStrategy() {
        require(msg.sender == owner() || msg.sender == strategy, "Auth failed");
        _;
    }

    modifier keeper() {
        require(isKeeper[msg.sender] == true || msg.sender == owner(), "not keeper");
        _;
    }

    // --- Setters ---

    function _initialLock() internal {
        //create new lock
        uint256 _strategyBalance = IERC20(pearl).balanceOf(strategy);
        ICaviarStrategy(strategy).createLock(_strategyBalance, MAXTIME);
        vePearlLastBalance = _strategyBalance;

        emit InitialLock(MAXTIME);
    }

    function _increaseAmount(uint256 _amount) internal {
        IERC20(pearl).safeTransfer(strategy, _amount);

        uint256 _pearlLocked = ICaviarStrategy(strategy).balanceOfVePearl();

        if (_pearlLocked > 0) {
            //increase amount
            ICaviarStrategy(strategy).increaseAmount(_amount);
            vePearlLastBalance += _amount;
        } else {
            _initialLock();
        }
        emit IncreaseAmount(_amount);
    }

    function setPromotionPeriod(bool _isPromotionPeriod, uint256 _depositFee) public onlyOwner {
        require(isPromotionPeriod == !_isPromotionPeriod, "Already set");
        isPromotionPeriod = _isPromotionPeriod;
        if (_isPromotionPeriod == true) {
            PROMO_VE_DEPOSIT_FEE = _depositFee;
        }

        emit SetPromotionPeriod(_isPromotionPeriod, _depositFee);
    }

    function setBeginTimestamp(uint256 _timestamp) external onlyOwner {
        beginTimestamp = _timestamp;

        emit SetBeginTimestamp(_timestamp);
    }

    function setPearlPair(address _pair) external onlyOwner {
        require(_pair != address(0), "addr 0");
        pearlPair = _pair;
        emit SetPearlPair(_pair);
    }

    function setPearl(address _pearl) external onlyOwner {
        require(_pearl != address(0), "addr 0");
        pearl = _pearl;
        emit SetPearl(_pearl);
    }

    function setVEPearl(address _vePearl) external onlyOwner {
        require(_vePearl != address(0), "addr 0");
        vePearl = _vePearl;
        emit SetPearl(_vePearl);
    }

    function enableVePearlDeposit() external onlyOwner {
        require(veDepositEnabled == false, "VePearl Depoist is already enabled");
        veDepositEnabled = true;
        emit EnableVePearlDeposit();
    }

    function disableVePearlDeposit() external onlyOwner {
        require(veDepositEnabled == true, "VePearl Depoist is already disabled");
        veDepositEnabled = false;
        emit DisableVePearlDeposit();
    }

    function enableRedeem() public onlyOwnerOrStrategy {
        redeemEnabled = true;
    }

    function disableRedeem() public onlyOwnerOrStrategy {
        redeemEnabled = false;
    }

    function addKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0));
        require(isKeeper[_keeper] == false);
        isKeeper[_keeper] = true;
        emit KeeperAdded(_keeper);
    }

    function removeKeeper(address _keeper) external onlyOwner {
        require(_keeper != address(0));
        require(isKeeper[_keeper] == true);
        isKeeper[_keeper] = false;
        emit KeeperRemoved(_keeper);
    }

    // --- Main functions ---

    function _deposit(uint256 _amount) internal {
        require(_amount != 0, "!>0");
        IERC20(pearl).safeTransferFrom(msg.sender, address(this), _amount);
        _increaseAmount(_amount);
        ICaviar(caviar).mint(msg.sender, _amount);

        emit Deposit(msg.sender, _amount);
    }

    //deposit 'underlying' for liVeNFT
    function deposit(uint256 _amount) external nonReentrant {
        _deposit(_amount);
    }

    function depositAll() external nonReentrant {
        uint256 _amount = IERC20(pearl).balanceOf(msg.sender);
        _deposit(_amount);
    }

    function depositNFT(uint256 _tokenId, uint256 _maxFee) public nonReentrant {
        require(veDepositEnabled, "NFT Deposit is not enabled");

        uint256 _depositFee;

        if (isPromotionPeriod) {
            _depositFee = PROMO_VE_DEPOSIT_FEE;
        } else {
            _depositFee = getCurrentDepositFee();
        }
        require(_depositFee <= _maxFee, "exceeded max deposit fee");

        (int128 _lockedAmount, ) = IVePearl(vePearl).locked(_tokenId);
        uint256 _locked = _int128ToUint256(_lockedAmount);

        uint256 _toMint = _locked.mul(MULTIPLIER - _depositFee).div(MULTIPLIER);

        IVePearl(vePearl).transferFrom(msg.sender, strategy, _tokenId);
        ICaviarStrategy(strategy).merge(_tokenId);
        vePearlLastBalance += _locked;

        mintedFromNftAt[getCurrentEpoch()] += _toMint;

        ICaviar(caviar).mint(msg.sender, _toMint);

        emit DepositNFT(msg.sender, _tokenId, _toMint);
    }

    function redeem(uint256 _amount) external nonReentrant {
        require(redeemEnabled, "Redeem disabled");
        uint256 _toRedeem = _amount.mul(MULTIPLIER - REDEEM_FEE).div(MULTIPLIER);
        ICaviarStrategy(strategy).splitAndSend(_toRedeem, msg.sender);
        vePearlLastBalance -= _toRedeem;
        ICaviar(caviar).burn(msg.sender, _amount);

        emit Redeem(msg.sender, _amount, _toRedeem);
    }

    function rebase() external keeper returns (uint256) {
        uint _before = vePearlLastBalance;
        ICaviarStrategy(strategy).claimRebase();
        vePearlLastBalance = ICaviarStrategy(strategy).balanceOfVePearl();
        uint _claimed = vePearlLastBalance.sub(_before);

        ICaviar(caviar).mint(feeManager, _claimed);
        ICaviarFeeManager(feeManager).distributeRebaseFees(_claimed);
        caviarSupplyAtCurrentEpoch = ICaviar(caviar).totalSupply();

        emit Rebase(_claimed);
        return _claimed;
    }

    function claimLPRewards() external keeper returns (uint256) {
        uint256 _amountClaimed = ICaviarChef(ICaviarFeeManager(feeManager).lpChef()).claimEmissions();

        // increase perl amount
        if (_amountClaimed != 0){
            _increaseAmount(_amountClaimed);
            // mint and send to fee distributor
            ICaviar(caviar).mint(feeManager, _amountClaimed);
            ICaviarFeeManager(feeManager).distributeEmissions(_amountClaimed);
            caviarSupplyAtCurrentEpoch = ICaviar(caviar).totalSupply();

            emit EmissionsClaimed(_amountClaimed);
        }
        return _amountClaimed;
    }

    // --- Getters ---

    function _getPearlPairAvgReserves() internal view returns (uint256 _caviarReserve, uint256 _pearlReserve) {
        IPearlPair.Observation memory _observation = IPearlPair(pearlPair).lastObservation();
        (uint256 _reserve0Cumulative, uint256 _reserve1Cumulative, ) = IPearlPair(pearlPair).currentCumulativePrices();
        if (block.timestamp == _observation.timestamp) {
            uint256 _observationLength = IPearlPair(pearlPair).observationLength();
            _observation = IPearlPair(pearlPair).observations(_observationLength - 2);
        }

        uint256 timeElapsed = block.timestamp - _observation.timestamp;
        uint256 _reserve0 = (_reserve0Cumulative - _observation.reserve0Cumulative) / timeElapsed;
        uint256 _reserve1 = (_reserve1Cumulative - _observation.reserve1Cumulative) / timeElapsed;

        if (caviar == IPearlPair(pearlPair).token0()) {
            (_caviarReserve, _pearlReserve) = (_reserve0, _reserve1);
        } else {
            (_caviarReserve, _pearlReserve) = (_reserve1, _reserve0);
        }
    }

    function _getPearlPairCurrentReserves() internal view returns (uint256 _caviarReserve, uint256 _pearlReserve) {
        uint256 _reserve0 = IPearlPair(pearlPair).reserve0();
        uint256 _reserve1 = IPearlPair(pearlPair).reserve1();

        if (caviar == IPearlPair(pearlPair).token0()) {
            (_caviarReserve, _pearlReserve) = (_reserve0, _reserve1);
        } else {
            (_caviarReserve, _pearlReserve) = (_reserve1, _reserve0);
        }
    }

    function getCurrentDepositFee() public view returns (uint256) {
        if (isPromotionPeriod) return PROMO_VE_DEPOSIT_FEE;

        if (pearlPair == address(0)) return MIN_VE_DEPOSIT_FEE;

        (uint256 _reserveCaviar, uint256 _reservePearl) = _getPearlPairAvgReserves();
        uint256 _depositFee;
        if (_reservePearl > 0) {
            _depositFee = _reserveCaviar.mul(MIN_VE_DEPOSIT_FEE).div(_reservePearl);
        }

        (_reserveCaviar, _reservePearl) = _getPearlPairCurrentReserves();
        if (_reservePearl > 0) {
            uint256 _depositFeeCurrent = _reserveCaviar.mul(MIN_VE_DEPOSIT_FEE).div(_reservePearl);
            if (_depositFeeCurrent > _depositFee) {
                _depositFee = _depositFeeCurrent;
            }
        }

        if (_depositFee < MIN_VE_DEPOSIT_FEE) {
            _depositFee = MIN_VE_DEPOSIT_FEE;
        }
        if (_depositFee > MAX_VE_DEPOSIT_FEE) {
            _depositFee = MAX_VE_DEPOSIT_FEE;
        }

        return _depositFee;
    }

    function getCurrentEpoch() public view returns (uint256 _epoch) {
        _epoch = (block.timestamp - beginTimestamp) / WEEK;
    }

    function _int128ToUint256(int128 _num) internal pure returns (uint256) {
        int256 _num256 = int256(_num);

        if (_num < 0) {
            _num256 = _num256 & int256(type(int128).max);
        }

        uint256 _result = uint256(_num256);
        return _result;
    }
}
