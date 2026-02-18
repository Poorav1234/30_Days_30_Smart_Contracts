// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Treasury is Ownable {
    event Paid(address indexed to, uint256 amount);
    event FeeUpdated(uint256 newFeeBps);

    uint256 public feeBps; // example parameter controlled by governance

    constructor(address owner_) Ownable(owner_) {}

    receive() external payable {}

    function pay(address payable to, uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "BAL");
        (bool ok, ) = to.call{value: amount}("");
        require(ok, "FAIL");
        emit Paid(to, amount);
    }

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "HIGH"); // <= 10%
        feeBps = newFeeBps;
        emit FeeUpdated(newFeeBps);
    }
}
