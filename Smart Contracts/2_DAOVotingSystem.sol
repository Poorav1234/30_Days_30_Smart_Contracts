// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract VotingSystem {

    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier checkOwner() {
        require(msg.sender == owner, "Only the owner can call this function");
        _;
    }

    struct Proposal {
        uint id;
        string description;
        uint yesVote;
        uint noVote;
        bool isActive;
    }

    uint public proposalCount;
    mapping(uint => Proposal) public proposals;
    mapping(uint => mapping(address => bool)) public hasVoted;

    function createProposal(string memory _description) public checkOwner {
        proposalCount++;
        proposals[proposalCount] = Proposal(
            proposalCount,
            _description,
            0,
            0,
            true
        );
    }

    function vote(uint _proposalId, bool _support) public {
        Proposal storage proposal = proposals[_proposalId];
        require(proposal.isActive, "Voting is closed");
        require(!hasVoted[_proposalId][msg.sender], "You have already voted");

        hasVoted[_proposalId][msg.sender] = true;

        if (_support) {
            proposal.yesVote++;
        } else {
            proposal.noVote++;
        }
    }

    function closeProposal(uint _proposalId) public checkOwner {
        proposals[_proposalId].isActive = false;
    }

    function getProposal(uint _proposalId)
        public
        view
        returns (string memory, uint, uint, bool)
    {
        Proposal memory proposal = proposals[_proposalId];
        return (
            proposal.description,
            proposal.yesVote,
            proposal.noVote,
            proposal.isActive
        );
    }
}
