// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IPearlPair.sol";
import "./interfaces/ICaviarChef.sol";

contract CaviarFeeManager is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    string public __NAME__;
    uint256 constant FEE_MAX = 1000;
    uint256 public FEE_CHEF;

    address public treasury;
    address public incentiveVault;

    address[] public tokens;

    address public pairFactory;
    address public caviarManager;

    mapping(address => bool) public isToken;
    mapping(address => bool) public isKeeper;

    address public caviar;
    address public usdr;
    address public usdc;
    address public wusdr;

    uint256 public feeStaking;
    uint256 public feeTngbl;
    uint256 public feeRebaseVault;
    uint256 public feeMultiplier;
    uint256 public pendingTngblFee;

    uint256 public lastStakingRebase;
    uint256 public lastLPRebase;

    address public stakingChef;
    address public rebaseChef;
    address public lpChef;

    address public pearlPair;

    event TokenConverted(address indexed token, uint256 amount, uint256 amountOut);
    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);
    event KeeperAdded(address indexed keeper);
    event KeeperRemoved(address indexed keeper);
    event FeesDistributed(address indexed token, uint256 amount, address indexed receiver);
    event EmergencyWithdrawal(address indexed token, uint256 amount);

    modifier keeper() {
        require(isKeeper[msg.sender] == true || msg.sender == owner(), "not keeper");
        _;
    }

    modifier restricted() {
        require(msg.sender == caviarManager || msg.sender == owner(), "not auth");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(string memory _name) public initializer {
        __Ownable_init();
        __NAME__ = _name;
    }

    /**
     * @notice Checks if there are any convertible rewards.
     * @return _canConvert Indicates if conversion is possible.
     * @return _token Token to convert.
     * @return _amount Amount to convert.
     */
    function checkConvertibleRewards() external view returns (bool _canConvert, address _token, uint256 _amount) {
        for (uint256 i = 0; i < tokens.length; i++) {
            _token = tokens[i];
            if (isToken[_token]) {
                _amount = IERC20(_token).balanceOf(address(this));
                if (_amount != 0) {
                    _canConvert = true;
                    break;
                }
            }
        }
    }

    /**
     * @notice Converts a specific reward token to USDR.
     * @param _token Token to convert.
     * @param _amount Amount to convert.
     * @param _target Target address for conversion.
     * @param _data Call data for conversion.
     */
    function convertRewardToken(address _token, uint256 _amount, address _target, bytes calldata _data) external keeper {
        require(isToken[_token], "invalid reward token");
        uint256 _before = IERC20(_token).balanceOf(address(this));
        uint256 _swapAmount = _amount == 0 ? _before : _amount;
        require(_before >= _swapAmount, "balance too low");
        uint256 _amountOut;
        if (_token != usdr) {
            _amountOut = _convertToken(_token, usdr, _swapAmount, _target, _data);
            require(_amountOut != 0, "insufficient output amount");
            uint256 _after = IERC20(_token).balanceOf(address(this));
            require(_after == _before - _swapAmount, "invalid input amount");
        } else {
            _amountOut = _amount;
        }
        emit TokenConverted(_token, _swapAmount, _amountOut);

        IERC20(usdr).safeApprove(wusdr, _amountOut);
        _amountOut = ERC4626(wusdr).deposit(_amountOut, address(this));

        _distributeStakingFees(_amountOut);
    }

    function _convertToken(
        address _tokenIn,
        address _tokenOut,
        uint256 _amount,
        address _target,
        bytes calldata _data
    ) internal returns (uint256 _amountOut) {
        uint256 _before = IERC20(_tokenOut).balanceOf(address(this));
        IERC20(_tokenIn).safeApprove(_target, 0);
        IERC20(_tokenIn).safeApprove(_target, _amount);
        (bool _success, ) = _target.call(_data);
        require(_success, "low swap level call failed");
        _amountOut = IERC20(_tokenOut).balanceOf(address(this)) - _before;
    }

    function addRewardToken(address _token) public onlyOwner {
        require(!isToken[_token], "already added");
        isToken[_token] = true;
        tokens.push(_token);
        emit TokenAdded(_token);
    }

    function addRewardTokens(address[] calldata _tokens) external onlyOwner {
        for (uint _i = 0; _i < _tokens.length; ) {
            address _token = _tokens[_i];
            if (!isToken[_token]) {
                isToken[_token] = true;
                tokens.push(_token);
                emit TokenAdded(_token);
            }
            unchecked {
                ++_i;
            }
        }
    }

    function removeRewardToken(address _token) external onlyOwner {
        require(isToken[_token], "token not added");
        isToken[_token] = false;
        uint256 _numTokens = tokens.length;
        for (uint256 _i = 0; _i < _numTokens; _i++) {
            if (tokens[_i] == _token) {
                tokens[_i] = tokens[_numTokens - 1];
                tokens.pop();
                break;
            }
        }
        emit TokenRemoved(_token);
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

    function setStakingChef(address _stakingChef) external onlyOwner {
        require(_stakingChef != address(0));
        stakingChef = _stakingChef;
    }

    function setRebaseChef(address _rebaseChef) external onlyOwner {
        require(_rebaseChef != address(0));
        rebaseChef = _rebaseChef;
    }

    function setLPChef(address _lpChef) external onlyOwner {
        require(_lpChef != address(0));
        lpChef = _lpChef;
    }

    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0));
        treasury = _treasury;
    }

    function setIncentiveVault(address _vault) external onlyOwner {
        require(_vault != address(0));
        incentiveVault = _vault;
    }

    function setCaviarManager(address _caviarManager) external onlyOwner {
        require(_caviarManager != address(0));
        caviarManager = _caviarManager;
    }

    function setCaviar(address _caviar) external onlyOwner {
        require(_caviar != address(0));
        caviar = _caviar;
    }

    function setUSDR(address _usdr) external onlyOwner {
        require(_usdr != address(0));
        usdr = _usdr;
    }

    function setUSDC(address _usdc) external onlyOwner {
        require(_usdc != address(0));
        usdc = _usdc;
    }

    function setWUSDR(address _wusdr) external onlyOwner {
        require(_wusdr != address(0));
        wusdr = _wusdr;
    }

    function setPearlPair(address _pair) external onlyOwner {
        require(_pair != address(0));
        pearlPair = _pair;
    }

    function setFees(uint256 _feeStaking, uint256 _feeTngbl, uint256 _feeRebaseVault) external onlyOwner {
        uint256 _feeMultiplier = _feeStaking + _feeTngbl;
        require(_feeRebaseVault <= _feeMultiplier, "Invalid fee values");
        feeStaking = _feeStaking;
        feeTngbl = _feeTngbl;
        feeRebaseVault = _feeRebaseVault;
        feeMultiplier = _feeMultiplier;
    }

    function _distributeStakingFees(uint256 _amount) internal {
        uint256 _amountStaking = _amount.mul(feeStaking).div(feeMultiplier);
        uint256 _amountTngbl = _amount.sub(_amountStaking);

        IERC20(wusdr).safeApprove(stakingChef, _amountStaking);
        ICaviarChef(stakingChef).seedRewards(_amountStaking);

        pendingTngblFee = pendingTngblFee + _amountTngbl;

        emit FeesDistributed(wusdr, _amountStaking, stakingChef);
    }

    function distributeStakingFees(uint256 _amount) external restricted {
        _distributeStakingFees(_amount);
    }

    function distributeTngblFees(uint256 _amount, address _target, bytes calldata _data) external keeper {
        require(treasury != address(0));
        require(_amount == pendingTngblFee, "invalid amount");
        pendingTngblFee = 0;

        _amount = ERC4626(wusdr).redeem(_amount, address(this), address(this));

        uint256 _amountOut = _convertToken(usdr, usdc, _amount, _target, _data);
        IERC20(usdc).safeTransfer(treasury, _amountOut);
        emit FeesDistributed(usdc, _amount, treasury);
    }

    function distributeEmissions(uint256 _amount) external restricted {
        IERC20(caviar).safeApprove(lpChef, _amount);
        ICaviarChef(lpChef).seedRewards(_amount);
    }

    function distributeRebaseFees(uint256 _amount) external restricted {
        (uint256 _caviarLP, ) = _getPearlPairReserves();
        uint256 _caviarRebase = IERC20(caviar).balanceOf(stakingChef);

        // take rebase fee, send to incentive vault:
        uint256 _amountLeft = _amount;
        if (incentiveVault != address(0)) {
            uint256 _incentiveAmount = _amount.mul(feeRebaseVault).div(feeMultiplier);
            IERC20(caviar).safeTransfer(incentiveVault, _incentiveAmount);
            _amountLeft = _amount.sub(_incentiveAmount);
        }

        // for remainder, split between rebase chef and LP:
        uint256 _caviarTotal = _caviarRebase.add(_caviarLP);
        uint256 _rebaseAmount = _amountLeft.mul(_caviarRebase).div(_caviarTotal);
        IERC20(caviar).safeApprove(rebaseChef, _rebaseAmount);
        ICaviarChef(rebaseChef).seedRewards(_rebaseAmount);
        lastStakingRebase = _rebaseAmount;
        _amountLeft = _amountLeft.sub(_rebaseAmount);
        IERC20(caviar).safeApprove(lpChef, _amountLeft);
        ICaviarChef(lpChef).seedRewards(_amountLeft);
        lastLPRebase = _amountLeft;
    }

    function emergencyWithdraw(address _token) external onlyOwner {
        uint256 _balance = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, _balance);
        emit EmergencyWithdrawal(_token, _balance);
    }

    function _getPearlPairReserves() internal view returns (uint256 _caviarReserve, uint256 _pearlReserve) {
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
}
