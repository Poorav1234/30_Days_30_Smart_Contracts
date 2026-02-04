// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.0/contracts/security/ReentrancyGuard.sol";

contract MiniDEX is ReentrancyGuard {

    IERC20 public tokenA;
    IERC20 public tokenB;

    uint256 public reserveA;
    uint256 public reserveB;

    uint256 public constant FEE_PERCENT = 3;
    uint256 public constant FEE_DENOMINATOR = 1000;

    event Swap(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    constructor(address _tokenA, address _tokenB) {
        tokenA = IERC20(_tokenA);
        tokenB = IERC20(_tokenB);
    }

    function addLiquidity(uint256 amountA, uint256 amountB) external nonReentrant {
        require(amountA > 0 && amountB > 0, "Invalid amounts");

        tokenA.transferFrom(msg.sender, address(this), amountA);
        tokenB.transferFrom(msg.sender, address(this), amountB);

        reserveA += amountA;
        reserveB += amountB;
    }

    function swapAforB(uint256 amountAIn) external nonReentrant {
        require(amountAIn > 0, "Invalid input");
        require(reserveA > 0 && reserveB > 0, "No liquidity");

        tokenA.transferFrom(msg.sender, address(this), amountAIn);

        uint256 amountInWithFee =
            (amountAIn * (FEE_DENOMINATOR - FEE_PERCENT)) / FEE_DENOMINATOR;

        uint256 amountBOut =
            (reserveB * amountInWithFee) / (reserveA + amountInWithFee);

        require(amountBOut > 0, "Insufficient output");

        tokenB.transfer(msg.sender, amountBOut);

        reserveA += amountAIn;
        reserveB -= amountBOut;

        emit Swap(
            msg.sender,
            address(tokenA),
            address(tokenB),
            amountAIn,
            amountBOut
        );
    }
}
