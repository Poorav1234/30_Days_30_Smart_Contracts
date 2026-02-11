// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

interface IFlashLoanReceiver {
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator
    ) external;
}

contract FlashLoan is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;

    uint256 public feeBps = 100;

    event FlashLoanExecuted(
        address indexed borrower,
        uint256 amount,
        uint256 fee
    );

    constructor(address _token) {
        require(_token != address(0), "Invalid token address");
        token = IERC20(_token);
    }

    function flashLoan(uint256 amount) external nonReentrant {
        require(amount > 0, "Amount must be > 0");

        uint256 balanceBefore = token.balanceOf(address(this));
        require(balanceBefore >= amount, "Insufficient liquidity");

        uint256 fee = (amount * feeBps) / 10000;

        token.safeTransfer(msg.sender, amount);

        IFlashLoanReceiver(msg.sender).executeOperation(
            address(token),
            amount,
            fee,
            msg.sender
        );

        uint256 balanceAfter = token.balanceOf(address(this));

        require(
            balanceAfter >= balanceBefore + fee,
            "Flash loan not repaid with fee"
        );

        emit FlashLoanExecuted(msg.sender, amount, fee);
    }

    function setFee(uint256 _feeBps) external {
        require(_feeBps <= 1000, "Fee too high"); 
        feeBps = _feeBps;
    }
}