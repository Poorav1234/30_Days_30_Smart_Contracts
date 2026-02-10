// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract DecentralizedLending {

    mapping(address => uint256) public deposits;
    mapping(address => uint256) public borrows;
    mapping(address => uint256) public collateral;

    uint256 public totalDeposits;
    uint256 public totalBorrows;

    uint256 public constant LTV = 70; 
    uint256 public constant LIQUIDATION_THRESHOLD = 75;
    uint256 public constant LIQUIDATION_BONUS = 10; // 10%

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Repaid(address indexed user, uint256 amount);
    event Liquidated(address indexed borrower, address indexed liquidator);

    function deposit() external payable {
        require(msg.value > 0, "Zero deposit");

        deposits[msg.sender] += msg.value;
        totalDeposits += msg.value;

        emit Deposited(msg.sender, msg.value);
    }

    function lockCollateral() external payable {
        require(msg.value > 0, "Zero collateral");
        collateral[msg.sender] += msg.value;
    }

    function borrow(uint256 amount) external {
        uint256 collateralValue = collateral[msg.sender];
        require(collateralValue > 0, "No collateral");

        uint256 maxBorrow =
            (collateralValue * LTV) / 100;

        require(borrows[msg.sender] + amount <= maxBorrow, "Exceeds limit");
        require(address(this).balance >= amount, "Insufficient liquidity");

        borrows[msg.sender] += amount;
        totalBorrows += amount;

        payable(msg.sender).transfer(amount);

        emit Borrowed(msg.sender, amount);
    }

    function repay() external payable {
        require(borrows[msg.sender] > 0, "No debt");
        require(msg.value <= borrows[msg.sender], "Overpay");

        borrows[msg.sender] -= msg.value;
        totalBorrows -= msg.value;

        emit Repaid(msg.sender, msg.value);
    }

    function healthFactor(address user) public view returns (uint256) {
        if (borrows[user] == 0) return type(uint256).max;

        uint256 adjustedCollateral =
            (collateral[user] * LIQUIDATION_THRESHOLD) / 100;

        return (adjustedCollateral * 1e18) / borrows[user];
    }

    function liquidate(address borrower) external {
        require(healthFactor(borrower) < 1e18, "Loan is healthy");

        uint256 collateralAmount = collateral[borrower];

        borrows[borrower] = 0;
        collateral[borrower] = 0;

        uint256 reward =
            (collateralAmount * (100 + LIQUIDATION_BONUS)) / 100;

        payable(msg.sender).transfer(reward);

        emit Liquidated(borrower, msg.sender);
    }

    receive() external payable {}
}