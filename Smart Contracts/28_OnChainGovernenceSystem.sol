// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    GovGovernor (bytecode reduced)
    - Uses OZ Governor + Votes + Counting + QuorumFraction + TimelockControl
    - Removes GovernorSettings (replaced by immutables) to reduce code size
*/

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";

contract GovGovernor is
    Governor,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    // ✅ Replace GovernorSettings with tiny storage (immutables save bytecode vs extension)
    uint48 private immutable _votingDelayBlocks;
    uint32 private immutable _votingPeriodBlocks;
    uint256 private immutable _proposalThresholdVotes;

    constructor(
        IVotes votesToken,
        TimelockController timelock,
        uint48 votingDelayBlocks,
        uint32 votingPeriodBlocks,
        uint256 proposalThresholdVotes,
        uint256 quorumPercent
    )
        Governor("OnChainGovernance")
        GovernorVotes(votesToken)
        GovernorVotesQuorumFraction(quorumPercent)
        GovernorTimelockControl(timelock)
    {
        _votingDelayBlocks = votingDelayBlocks;
        _votingPeriodBlocks = votingPeriodBlocks;
        _proposalThresholdVotes = proposalThresholdVotes;
    }

    // -------------------- settings (instead of GovernorSettings) --------------------

    function votingDelay() public view override returns (uint256) {
        return _votingDelayBlocks;
    }

    function votingPeriod() public view override returns (uint256) {
        return _votingPeriodBlocks;
    }

    function proposalThreshold() public view override returns (uint256) {
        return _proposalThresholdVotes;
    }

    // -------------------- required overrides --------------------

    function quorum(uint256 timepoint)
        public
        view
        override(Governor, GovernorVotesQuorumFraction)
        returns (uint256)
    {
        return super.quorum(timepoint);
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint48)
    {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
    {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    )
        internal
        override(Governor, GovernorTimelockControl)
        returns (uint256)
    {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor()
        internal
        view
        override(Governor, GovernorTimelockControl)
        returns (address)
    {
        return super._executor();
    }

    // ✅ Fix for your OZ behavior: don't include GovernorTimelockControl here
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
