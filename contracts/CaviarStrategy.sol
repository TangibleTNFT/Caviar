// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IVePearl.sol";
import "./interfaces/IVoter.sol";
import "./interfaces/IPearlGauge.sol";
import "./interfaces/IRewardsDistributor.sol";
import "./interfaces/ICaviarManager.sol";
import "./interfaces/IPearlBribes.sol";

contract CaviarStrategy is OwnableUpgradeable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    string public __NAME__;
    struct VoteInfo {
        address[] pairs;
        uint256[] weights;
    }

    VoteInfo lastVote;

    address public vePearl;
    address public pearl;
    address public caviarManager;
    address public pearlVoter;
    address public feeManager;
    address public pearlRewardsDistributor;
    address public cvrPearlGauge;

    mapping(address => bool) isBoostStrategy;
    mapping(address => bool) public isAllowedVoter;

    uint256 public tokenId;
    uint256 public MAX_TIME;
    uint256 public WEEK;

    mapping(uint256 => uint256) public tokenIdAt;
    mapping(uint256 => VoteInfo) voteInfoAt;
    mapping(address => bool) public isKeeper;
    mapping(address => uint256) public lastBribe;
    address[] public bribeTokens;

    address public manualFeeManager;
    bool public isManual;

    event Merge(uint256 indexed from);
    event KeeperAdded(address indexed keeper);
    event KeeperRemoved(address indexed keeper);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        address _pearl,
        address _vePearl,
        address _pearlVoter,
        address _feeManager,
        address _pearlRewardsDistributor,
        uint _lockingYear // eg.: crv = 4, lqdr = 2
    ) public initializer {
        __Ownable_init();
        __NAME__ = _name;

        pearl = _pearl;
        vePearl = _vePearl;
        require(_pearl == IVePearl(vePearl).token(), "not same token");

        pearlVoter = _pearlVoter;
        feeManager = _feeManager;
        pearlRewardsDistributor = _pearlRewardsDistributor;

        MAX_TIME = _lockingYear * 364 * 86400;
        WEEK = 7 * 86400;
    }

    modifier restricted() {
        require(msg.sender == owner() || msg.sender == caviarManager, "Auth failed");
        _;
    }

    modifier ownerOrAllowedVoter() {
        require(msg.sender == owner() || isAllowedVoter[msg.sender], "Permission denied");
        _;
    }

    function getLastVote() external view returns (VoteInfo memory) {
        return lastVote;
    }

    modifier keeper() {
        require(isKeeper[msg.sender] == true || msg.sender == owner(), "not keeper");
        _;
    }

    /*
        -------------------
        Setters
        -------------------
    */

    function setVoter(address _voter) external onlyOwner {
        require(_voter != address(0), "addr 0");
        pearlVoter = _voter;
    }

    function setcvrPearlGauge(address _cvrPearlGauge) external onlyOwner {
        require(_cvrPearlGauge != address(0), "addr 0");
        cvrPearlGauge = _cvrPearlGauge;
    }

    function setPearlRewardsDistributor(address _pearlRewardsDistributor) external onlyOwner {
        require(_pearlRewardsDistributor != address(0), "addr 0");
        pearlRewardsDistributor = _pearlRewardsDistributor;
    }

    function setCaviarManager(address _manager) external onlyOwner {
        require(_manager != address(0), "addr 0");
        caviarManager = _manager;
    }

    function setPearl(address _pearl) external onlyOwner {
        require(_pearl != address(0), "addr 0");
        pearl = _pearl;
    }

    function setVEPearl(address _vePearl) external onlyOwner {
        require(_vePearl != address(0), "addr 0");
        vePearl = _vePearl;
    }

    function setPearlVoter(address _pearlVoter) external onlyOwner {
        require(_pearlVoter != address(0), "addr 0");
        pearlVoter = _pearlVoter;
    }

    function whitelistVoter(address _voter) external onlyOwner {
        isAllowedVoter[_voter] = true;
    }

    function blacklistVoter(address _voter) external onlyOwner {
        isAllowedVoter[_voter] = false;
    }

    function setManualFeeManager(address _manager) external onlyOwner {
        require(_manager != address(0), "addr 0");
        manualFeeManager = _manager;
    }

    function setIsManual(bool _isManual) external onlyOwner {
        isManual = _isManual;
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

    /*  
        -------------------
        vePearl MANAGMENT
        -------------------
    */

    function createLock(uint256 _amount, uint256 _unlockTime) external restricted {
        require(tokenId == 0, "Already locked");
        uint256 _balance = IERC20(pearl).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds balance");
        IERC20(pearl).safeApprove(vePearl, 0);
        IERC20(pearl).safeApprove(vePearl, _amount);
        tokenId = IVePearl(vePearl).create_lock(_amount, _unlockTime);
    }

    function release() external restricted {
        IVePearl(vePearl).withdraw(tokenId);
    }

    function increaseAmount(uint256 _amount) external restricted {
        _increaseAmount(_amount);
    }

    function _increaseAmount(uint256 _amount) internal {
        uint256 _balance = IERC20(pearl).balanceOf(address(this));
        require(_amount <= _balance, "Amount exceeds pearl balance");
        IERC20(pearl).safeApprove(vePearl, 0);
        IERC20(pearl).safeApprove(vePearl, _amount);
        IVePearl(vePearl).increase_amount(tokenId, _amount);
    }

    function _increaseTime(uint256 _unlockTime) internal {
        IVePearl(vePearl).increase_unlock_time(tokenId, _unlockTime);
    }

    function increaseTime(uint256 _unlockTime) external ownerOrAllowedVoter {
        _increaseTime(_unlockTime);
    }

    function increaseTimeMax() external {
        _increaseTime(MAX_TIME);
    }

    function balanceOfVePearl() public view returns (uint256) {
        (int128 amount, ) = IVePearl(vePearl).locked(tokenId);
        return uint256(uint128(amount));
    }

    /*  
        -------------------
        VOTING AND CLAIMING
        -------------------
    */

    function claimBribe(address[] memory _bribes, address[][] memory _tokens) external keeper {
        // clear previous bribe data:
        uint256 i = 0;
        for (; i < bribeTokens.length; ++i) {
            delete lastBribe[bribeTokens[i]];
        }
        delete bribeTokens;

        // claim new vote:
        IVoter(pearlVoter).claimBribes(_bribes, _tokens, tokenId);
        i = 0;
        uint256 k = 0;
        uint256 _len1 = _bribes.length;
        uint256 _len2;
        uint256 _amount = 0;
        address _token;
        for (i; i < _len1; i++) {
            _len2 = _tokens[i].length;
            for (k = 0; k < _len2; k++) {
                _token = _tokens[i][k];
                _amount = IERC20(_token).balanceOf(address(this));
                if (_amount != 0) {
                    lastBribe[_token] = _amount;
                    bribeTokens.push(_token);
                    if (isManual && manualFeeManager != address(0)) {
                        IERC20(_token).safeTransfer(manualFeeManager, _amount);
                    } else {
                        IERC20(_token).safeTransfer(feeManager, _amount);
                    }
                }
            }
        }
    }

    function claimFee(address[] memory _fees, address[][] memory _tokens) external keeper {
        IVoter(pearlVoter).claimFees(_fees, _tokens, tokenId);
        uint256 i = 0;
        uint256 k = 0;
        uint256 _len1 = _fees.length;
        uint256 _len2;
        uint256 _amount = 0;
        address _token;
        for (i; i < _len1; i++) {
            _len2 = _tokens[i].length;
            for (k = 0; k < _len2; k++) {
                _token = _tokens[i][k];
                _amount = IERC20(_token).balanceOf(address(this));
                if (_amount != 0) {
                    if (isManual && manualFeeManager != address(0)) {
                        IERC20(_token).safeTransfer(manualFeeManager, _amount);
                    } else {
                        IERC20(_token).safeTransfer(feeManager, _amount);
                    }
                }
            }
        }
    }

    function claimRebase() external restricted {
        IRewardsDistributor(pearlRewardsDistributor).claim(tokenId);
        // _resetVote();
    }

    function vote(address[] calldata _pool, uint256[] calldata _weights) external ownerOrAllowedVoter {
        _vote(_pool, _weights);
    }

    function _vote(address[] memory _pool, uint256[] memory _weights) internal {
        require(_pool.length == _weights.length, "Token length doesn't match");
        uint256 _length = _pool.length;
        IVoter(pearlVoter).vote(tokenId, _pool, _weights);

        VoteInfo memory _lastVote;
        _lastVote.pairs = new address[](_length);
        _lastVote.pairs = _pool;

        _lastVote.weights = new uint[](_length);
        _lastVote.weights = _weights;

        lastVote = _lastVote;

        // ICaviarManager(caviarManager).disableRedeem();

        tokenIdAt[ICaviarManager(caviarManager).getCurrentEpoch()] = tokenId;
        voteInfoAt[ICaviarManager(caviarManager).getCurrentEpoch()] = lastVote;
    }

    function _pokeVote() internal {
        uint256 _currentEpoch = ICaviarManager(caviarManager).getCurrentEpoch();
        if (tokenIdAt[_currentEpoch] > 0) {
            _vote(voteInfoAt[_currentEpoch].pairs, voteInfoAt[_currentEpoch].weights);
        }
    }

    function merge(uint256 from) external restricted {
        require(from != tokenId, "Can't merge from main tokenId");
        IVePearl(vePearl).merge(from, tokenId);
        emit Merge(from);
    }

    function splitAndSend(uint256 _toSplit, address _to) external restricted {
        _resetVote();
        uint256 _totalBalance = balanceOfVePearl();
        uint256 _totalBalanceAfter = _totalBalance.sub(_toSplit);
        uint256[] memory _amounts = new uint[](2);
        _amounts[0] = _totalBalanceAfter;
        _amounts[1] = _toSplit;

        IVePearl(vePearl).split(_amounts, tokenId);
        uint256 _splitTokenId = IVePearl(vePearl).tokenId();

        IVePearl(vePearl).transferFrom(address(this), _to, _splitTokenId);

        _pokeVote();
    }

    function _resetVote() internal {
        IVoter(pearlVoter).reset(tokenId);
    }

    function resetVote() external onlyOwner {
        _resetVote();
    }
}
