// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Escrow {
    address public buyer;
    address public seller;

    uint public escrowAmount;

    bool public buyerApproved;
    bool public sellerApproved;

    bool public isReleased;

    event BuyerApproved(address buyer);
    event SellerApproved(address seller);
    event FundsReleased(address seller, uint amount);

    constructor(address _seller) payable {
        require(_seller != address(0), "Invalid seller address");
        require(msg.value > 0, "Escrow amount must be greater than 0");

        buyer = msg.sender;
        seller = _seller;
        escrowAmount = msg.value;
    }

    function buyerApproval() external {
        require(msg.sender == buyer, "Only buyer can approve");
        require(!buyerApproved, "Buyer already approved");

        buyerApproved = true;
        emit BuyerApproved(buyer);
    }

    function sellerApproval() external {
        require(msg.sender == seller, "Only seller can approve");
        require(!sellerApproved, "Seller already approved");

        sellerApproved = true;
        emit SellerApproved(seller);
    }

    function releaseFunds() external {
        require(msg.sender == seller, "Only seller can release funds");
        require(buyerApproved && sellerApproved, "Both approvals required");
        require(!isReleased, "Funds already released");

        isReleased = true;

        payable(seller).transfer(escrowAmount);
        emit FundsReleased(seller, escrowAmount);
    }
}
