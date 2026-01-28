// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract TimeLockedWallet {
    
    struct Wallet {
        uint balance;
        uint unlockTime;
    }

    mapping(address => Wallet) public wallets;

    function deposit(uint _unlockTime) external payable {
        require(msg.value > 0, "No ETH sent");
        require(_unlockTime > block.timestamp, "Unlocking time must be greater than current time");

        wallets[msg.sender].balance += msg.value;
        wallets[msg.sender].unlockTime = _unlockTime;
    }

    function withdraw() external {
        Wallet storage userWallet = wallets[msg.sender];
        require(block.timestamp >= userWallet.unlockTime, "Still locked");
        require(userWallet.balance > 0, "No funds");

        uint256 amount = userWallet.balance;
        userWallet.balance = 0;

        payable(msg.sender).transfer(amount);
    }

    function timeleft(address user) external view returns (uint){
        if (block.timestamp >= wallets[user].unlockTime) {
            return 0;
        }
        return wallets[user].unlockTime - block.timestamp;
    }
}