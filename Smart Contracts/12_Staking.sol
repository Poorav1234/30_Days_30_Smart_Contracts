// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Staking is ReentrancyGuard{
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    uint256 public rewardRate;
    uint256 public totalStaked;

    mapping(address => uint256) public stakedBalance;
    mapping(address => uint256) public lastUpdateTime;
    mapping(address => uint256) public rewards;

    constructor(address _stakingToken, address _rewardToken, uint256 _rewardRate){
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardRate = _rewardRate;
    }

    function earned(address user) public view returns (uint256){
        uint256 timeDiff = block.timestamp - lastUpdateTime[user];
        return (stakedBalance[user] * rewardRate * timeDiff) / 1e18;
    }

    modifier updateReward(address user){
        if (user != address(0)) {
            rewards[user] += earned(user);
            lastUpdateTime[user] = block.timestamp;
        }
        _;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender){
        require(amount > 0, "Cannot stake 0");
        stakingToken.transferFrom(msg.sender, address(this), amount);

        stakedBalance[msg.sender] += amount;
        totalStaked += amount;
    }

    function unstake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        require(amount > 0, "Cannot unstake 0");
        require(stakedBalance[msg.sender] >= amount, "Insufficient stake");

        stakedBalance[msg.sender] -= amount;
        totalStaked -= amount;

        stakingToken.transfer(msg.sender, amount);
    }

    function claimRewards() external nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        require(reward > 0, "No rewards");

        rewards[msg.sender] = 0;
        rewardToken.transfer(msg.sender, reward);
    }
}