// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract GovernanceToken {
    string public name = "Governance Token";
    string public symbol = "GOV";
    uint8 public decimals = 18;
    uint public totalSupply;

    mapping(address => uint) public balanceOf;

    constructor(uint _supply) {
        totalSupply = _supply;
        balanceOf[msg.sender] = _supply;
    }

    function transfer(address to, uint amount) external {
        require(balanceOf[msg.sender] >= amount, "Not enough tokens");

        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

}
