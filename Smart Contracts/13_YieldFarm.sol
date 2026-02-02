// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";

contract YieldFarming is ReentrancyGuard {

    IERC20 public stakingToken;
    IERC20 public rewardToken;

    uint256 public rewardRate;
    uint256 public totalStaked;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public balances;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);

    constructor(
        address _stakingToken,
        address _rewardToken,
        uint256 _rewardRate
    ) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
        lastUpdateTime = block.timestamp;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored +
            ((lastTimeRewardApplicable() - lastUpdateTime)
                * rewardRate * 1e18) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        return
            (balances[account]
                * (rewardPerToken() - userRewardPerTokenPaid[account])
                ) / 1e18
            + rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    /*
        Stake tokens into the liquidity pool
    */
    function stake(uint256 amount)
        external
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot stake zero");

        totalStaked += amount;
        balances[msg.sender] += amount;

        stakingToken.transferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, amount);
    }

    
    function withdraw(uint256 amount)
        public
        nonReentrant
        updateReward(msg.sender)
    {
        require(amount > 0, "Cannot withdraw zero");
        require(balances[msg.sender] >= amount, "Insufficient balance");

        totalStaked -= amount;
        balances[msg.sender] -= amount;

        stakingToken.transfer(msg.sender, amount);

        emit Withdrawn(msg.sender, amount);
    }

    function claimReward()
        public
        nonReentrant
        updateReward(msg.sender)
    {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards");

        rewards[msg.sender] = 0;

        rewardToken.transfer(msg.sender, reward);

        emit RewardPaid(msg.sender, reward);
    }

    function exit() external {
        withdraw(balances[msg.sender]);
        claimReward();
    }
}