// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    OPTIONAL helper: one-time setup script-like contract.
    Many teams do this in a deployment script instead (Hardhat/Foundry).
    This shows the REQUIRED role wiring for timelock:
    - Governor should be proposer
    - Anyone (or Governor) should be executor depending on your model
    - Remove admin powers from deployer after setup
*/

import "@openzeppelin/contracts/governance/TimelockController.sol";

contract TimelockConfigurator {
    function configure(
        TimelockController timelock,
        address governor,
        address deployerAdminToRevoke,
        bool openExecution
    ) external {
        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
        bytes32 CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        bytes32 DEFAULT_ADMIN_ROLE = timelock.DEFAULT_ADMIN_ROLE();

        // Governor becomes proposer + canceller (optional canceller)
        timelock.grantRole(PROPOSER_ROLE, governor);
        timelock.grantRole(CANCELLER_ROLE, governor);

        // Executor can be open to all (address(0)) or restricted to governor/timelock itself
        if (openExecution) {
            timelock.grantRole(EXECUTOR_ROLE, address(0));
        } else {
            timelock.grantRole(EXECUTOR_ROLE, governor);
        }

        // Revoke deployer admin so governance is truly decentralized
        timelock.revokeRole(DEFAULT_ADMIN_ROLE, deployerAdminToRevoke);
    }
}
