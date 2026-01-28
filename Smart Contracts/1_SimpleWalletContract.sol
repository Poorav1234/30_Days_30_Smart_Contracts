// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SmartWalletContract {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    modifier checkOwner {
        require(msg.sender == owner, "Only owner can perform this action");
        _;
    }

    function deposit() public payable {
        require(msg.value > 0, "Deposit amount must be greater than zero");
    }

    function withdraw(uint ethValue) public checkOwner {
        require(address(this).balance >= ethValue, "Balance is not sufficient");

        (bool success, ) = payable(owner).call{value: ethValue}("");
        require(success, "Withdrawal failed");
    }

    function sendEth(address payable receiver, uint amount) public checkOwner {
        require(receiver != address(0), "Invalid receiver address");
        require(amount > 0, "Amount must be greater than zero");
        require(address(this).balance >= amount, "Insufficient wallet balance");

        (bool success, ) = receiver.call{value: amount}("");
        require(success, "ETH transfer failed");
    }

    function getBalance() public view returns (uint) {
        return address(this).balance;
    }

    receive() external payable {}
}
