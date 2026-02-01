// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v5.0.1/contracts/utils/ReentrancyGuard.sol";

contract Staking is ReentrancyGuard{
    IERC20 public stakingToken; // 0xd8b934580fcE35a11B58C6D73aDeE468a2833fa8 STK
    IERC20 public rewardToken; // 0xf8e81D47203A594245E36C48e151709F0C19fBe8 RWD

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