// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashLoan {
    function flashLoan(uint256 amount) external;
}

interface IFlashLoanReceiver {
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator
    ) external;
}

contract FlashLoanBorrower is IFlashLoanReceiver {

    IFlashLoan public lender;
    IERC20 public token;
    address public owner;

    constructor(address _lender, address _token) {
        lender = IFlashLoan(_lender);
        token = IERC20(_token);
        owner = msg.sender;
    }

    function startFlashLoan(uint256 amount) external {
        require(msg.sender == owner, "Not owner");
        lender.flashLoan(amount);
    }

    function executeOperation(
        address _token,
        uint256 amount,
        uint256 fee,
        address
    ) external override {

        require(msg.sender == address(lender), "Only lender can call");

        uint256 totalRepayment = amount + fee;

        IERC20(_token).transfer(address(lender), totalRepayment);
    }
}