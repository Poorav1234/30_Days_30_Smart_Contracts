// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CrossChainBridge {
    using SafeERC20 for IERC20;

    address public admin;  
    IERC20 public token;  

    event Deposit(address indexed user, uint256 amount, uint256 targetChainId, bytes targetAddress);
    event Withdrawal(address indexed user, uint256 amount, uint256 sourceChainId);

    // Track processed cross-chain withdrawals to prevent double spending
    mapping(bytes32 => bool) public processedTransfers;

    constructor(address _token) {
        admin = msg.sender;
        token = IERC20(_token);
    }

    function deposit(uint256 amount, uint256 targetChainId, bytes calldata targetAddress) external {
        require(amount > 0, "Amount must be > 0");
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposit(msg.sender, amount, targetChainId, targetAddress);
    }

    // Withdraw tokens from the bridge (called after validator confirms deposit on other chain)
    function withdraw(address user, uint256 amount, uint256 sourceChainId, bytes32 txHash) external {
        require(msg.sender == admin, "Only admin can withdraw");
        require(!processedTransfers[txHash], "Transfer already processed");
        processedTransfers[txHash] = true;
        token.safeTransfer(user, amount);
        emit Withdrawal(user, amount, sourceChainId);
    }

    // Optional: Admin can update the token contract if needed
    function updateToken(address _token) external {
        require(msg.sender == admin, "Only admin");
        token = IERC20(_token);
    }

    function updateAdmin(address newAdmin) external {
        require(msg.sender == admin, "Only admin");
        admin = newAdmin;
    }
}
