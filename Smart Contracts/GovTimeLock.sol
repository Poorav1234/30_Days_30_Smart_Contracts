// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/governance/TimelockController.sol";

contract GovTimelock is TimelockController {
    constructor(
        uint256 minDelaySeconds,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelaySeconds, proposers, executors, admin) {}
}
