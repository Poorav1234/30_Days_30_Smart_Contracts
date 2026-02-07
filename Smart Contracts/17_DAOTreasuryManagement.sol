// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IERC20 {
    function balanceOf(address user) external view returns (uint);
    function totalSupply() external view returns (uint);
}

contract DAOTreasuryERC20 {

    IERC20 public governanceToken;
    uint public quorumPercent = 20;

    constructor(address _token) {
        governanceToken = IERC20(_token);
    }

    struct Proposal {
        address proposer;
        address payable recipient;
        uint amount;
        string description;
        uint voteCount;
        uint deadline;
        bool executed;
        bool canceled;
    }

    Proposal[] public proposals;
    mapping(uint => mapping(address => bool)) public voted; 

    receive() external payable {}

    function createProposal( address payable _recipient, uint _amount, string calldata _description ) external {

        require( governanceToken.balanceOf(msg.sender) > 0, "No governance tokens" );
        require(address(this).balance >= _amount, "Insufficient treasury");

        proposals.push(
            Proposal({
                proposer: msg.sender,
                recipient: _recipient,
                amount: _amount,
                description: _description,
                voteCount: 0,
                deadline: block.timestamp + 3 days,
                executed: false,
                canceled: false
            })
        );
    }

    function vote(uint proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(block.timestamp < proposal.deadline, "Voting ended");
        require(!proposal.canceled, "Proposal canceled");
        require(!voted[proposalId][msg.sender], "Already voted");

        uint votingPower = governanceToken.balanceOf(msg.sender);
        require(votingPower > 0, "No voting power");

        voted[proposalId][msg.sender] = true;
        proposal.voteCount += votingPower;
    }

    function cancelProposal(uint proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(msg.sender == proposal.proposer, "Not proposer");
        require(!proposal.executed, "Already executed");

        proposal.canceled = true;
    }

    function executeProposal(uint proposalId) external {
        Proposal storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.deadline, "Voting active");
        require(!proposal.executed, "Already executed");
        require(!proposal.canceled, "Proposal canceled");

        uint totalSupply = governanceToken.totalSupply();
        uint quorumVotes = (totalSupply * quorumPercent) / 100;

        require(proposal.voteCount >= quorumVotes, "Quorum not met");
        require(address(this).balance >= proposal.amount, "Insufficient funds");

        proposal.executed = true;
        proposal.recipient.transfer(proposal.amount);
    }

    function getProposalsCount() external view returns (uint) {
        return proposals.length;
    }

    function getTreasuryBalance() external view returns (uint) {
        return address(this).balance;
    }

    function fundTreasury() external payable {
        require(msg.value > 0, "Send some ETH");
    }
}