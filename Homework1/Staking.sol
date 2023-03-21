// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Staking is ReentrancyGuard, Pausable, Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    // 奖励代币合约地址
    IERC20 public rewardsToken;

    // 质押代币合约地址
    IERC20 public stakingToken;

    // 质押奖励的发放速率
    uint256 public rewardRate = 0;

    // 每次有用户操作时，更新为当前时间
    uint256 public lastUpdateTime;

    // 我们前面说到的每单位数量获得奖励的累加值，这里是乘上奖励发放速率后的值
    uint256 public rewardPerTokenStored;

    // 在单个用户维度上，为每个用户记录每次操作的累加值，同样也是乘上奖励发放速率后的值
    mapping(address => uint256) public userRewardPerTokenPaid;

    // 用户到当前时刻可领取的奖励数量
    mapping(address => uint256) public rewards;

    // 池子中质押总量
    uint256 private _totalSupply;

    // 用户的余额
    mapping(address => uint256) private _balances;

    uint256 public periodFinish = 0;
    uint256 public rewardsDuration = 7 days;

    constructor(address _rewardsToken, address _stakingToken) {
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    // 计算当前时刻的累加值
    function rewardPerToken() public view returns (uint256) {
        // 如果池子里的数量为0，说明上一个区间内没有必要发放奖励，因此累加值不变
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        // 计算累加值，上一个累加值加上最近一个区间的单位数量可获得的奖励数量
        return
            rewardPerTokenStored.add(
                lastTimeRewardApplicable()
                    .sub(lastUpdateTime)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(_totalSupply)
            );
    }

    // 计算用户可以领取的奖励数量
    // 质押数量 * （当前累加值 - 用户上次操作时的累加值）+ 上次更新的奖励数量
    function earned(address account) public view returns (uint256) {
        return
            _balances[account]
                .mul(rewardPerToken().sub(userRewardPerTokenPaid[account]))
                .div(1e18)
                .add(rewards[account]);
    }

    // 获取当前有效时间，如果活动结束了，就用结束时间，否则就用当前时间
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function getRewardForDuration() external view returns (uint256) {
        return rewardRate.mul(rewardsDuration);
    }


    function stake(uint256 amount)
        external
        nonReentrant
        whenNotPaused
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake 0");
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw 0");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        withdraw(_balances[msg.sender]);
        getReward();
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function notifyRewardAmount(uint256 reward)
        external
        onlyOwner
        updateReward(address(0))
    {
        if (block.timestamp >= periodFinish) {
            rewardRate = reward.div(rewardsDuration);
        } else {
            uint256 remaining = periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(rewardRate);
            rewardRate = reward.add(leftover).div(rewardsDuration);
        }
        uint256 balance = rewardsToken.balanceOf(address(this));
        require(
            rewardRate <= balance.div(rewardsDuration),
            "Provided reward too high"
        );

        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp.add(rewardsDuration);
        emit RewardAdded(reward);
    }

    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        require(
            block.timestamp > periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(rewardsDuration);
    }

    modifier updateReward(address account) {
        // 更新累加值
        rewardPerTokenStored = rewardPerToken();
        // 更新最新有效时间戳
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            // 更新奖励数量
            rewards[account] = earned(account);
            // 更新用户的累加值
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }


    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
}
