// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CrowdFunding {

    uint public campaignCount;

    struct Campaign {
        address owner;
        uint goalAmount;
        uint deadline;
        uint amountRaised;
        bool goalReached;
        bool fundsWithdrawn;
        mapping(address => uint) contributions;
    }

    mapping(uint => Campaign) public campaigns;

    event CampaignCreated(uint campaignId, address owner, uint goalAmount, uint deadline);
    event DonationReceived(uint campaignId, address donor, uint amount);
    event FundsWithdrawn(uint campaignId, address owner, uint amount);
    event RefundIssued(uint campaignId, address donor, uint amount);

    function createCampaign(uint _goalAmount, uint _durationInSeconds) public {
        campaignCount++;
        Campaign storage c = campaigns[campaignCount];
        c.owner = msg.sender;
        c.goalAmount = _goalAmount;
        c.deadline = block.timestamp + _durationInSeconds;
        emit CampaignCreated(campaignCount, msg.sender, _goalAmount, c.deadline);
    }

    function donate(uint _campaignId) public payable {
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp < c.deadline, "Campaign ended");
        c.amountRaised += msg.value;
        c.contributions[msg.sender] += msg.value;
        if (c.amountRaised >= c.goalAmount) {
            c.goalReached = true;
        }
        emit DonationReceived(_campaignId, msg.sender, msg.value);
    }

    function withdrawFunds(uint _campaignId) public {
        Campaign storage c = campaigns[_campaignId];
        require(msg.sender == c.owner, "Not campaign owner");
        require(c.goalReached, "Goal not reached");
        require(!c.fundsWithdrawn, "Already withdrawn");

        c.fundsWithdrawn = true;
        (bool success, ) = payable(c.owner).call{value: c.amountRaised}("");
        require(success, "Transfer failed");

        emit FundsWithdrawn(_campaignId, c.owner, c.amountRaised);
    }

    function refund(uint _campaignId) public {
        Campaign storage c = campaigns[_campaignId];
        require(block.timestamp > c.deadline, "Campaign active");
        require(!c.goalReached, "Goal reached");

        uint amount = c.contributions[msg.sender];
        require(amount > 0, "No contribution");

        c.contributions[msg.sender] = 0;
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Refund failed");

        emit RefundIssued(_campaignId, msg.sender, amount);
    }
}
