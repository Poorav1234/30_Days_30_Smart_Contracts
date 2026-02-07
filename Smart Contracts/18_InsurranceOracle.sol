// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract InsuranceOracle {

    address public owner;
    address public oracle;

    uint256 public oracleData; 

    struct Policy {
        uint256 premium;
        uint256 payout;
        bool isActive;
        bool claimed;
    }

    mapping(address => Policy) public policies;

    event PolicyPurchased(address indexed user, uint256 premium, uint256 payout);
    event OracleUpdated(uint256 data);
    event ClaimPaid(address indexed user, uint256 payout);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlyOracle() {
        require(msg.sender == oracle, "Not oracle");
        _;
    }

    constructor(address _oracle) {
        owner = msg.sender;
        oracle = _oracle;
    }

    function buyPolicy(uint256 _payout) external payable {
        require(msg.value > 0, "Premium required");
        require(!policies[msg.sender].isActive, "Policy already active");

        policies[msg.sender] = Policy({
            premium: msg.value,
            payout: _payout,
            isActive: true,
            claimed: false
        });

        emit PolicyPurchased(msg.sender, msg.value, _payout);
    }

    function updateOracleData(uint256 _data) external onlyOracle {
        oracleData = _data;
        emit OracleUpdated(_data);
    }

    function claim() external {
        Policy storage policy = policies[msg.sender];

        require(policy.isActive, "No active policy");
        require(!policy.claimed, "Already claimed");
        require(oracleData > 100, "Claim condition not met");

        policy.claimed = true;
        policy.isActive = false;

        payable(msg.sender).transfer(policy.payout);

        emit ClaimPaid(msg.sender, policy.payout);
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
    }

    function withdrawFunds(uint256 amount) external onlyOwner {
        payable(owner).transfer(amount);
    }

    function getPolicy(address user) external view returns (Policy memory) {
        return policies[user];
    }

    receive() external payable {}

    function fundPool() external payable onlyOwner {
        require(msg.value > 0, "Send ETH to fund pool");
    }
}