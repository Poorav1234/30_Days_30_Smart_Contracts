// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract DecentralizedMarketplace {

    enum OrderStatus {
        Listed,
        Paid,
        Shipped,
        Completed,
        Refunded
    }

    struct Product {
        uint id;
        string name;
        uint price;
        address payable seller;
        address buyer;
        OrderStatus status;
    }
    
    uint public productCount;
    address public owner;
    uint public platformFeePercentage = 2;

    mapping (uint => Product) public products;

    event ProductListed(uint256 indexed id, string name, uint256 price, address seller);
    event ProductPaid(uint256 indexed id, address buyer);
    event ProductShipped(uint256 indexed id);
    event ProductCompleted(uint256 indexed id);
    event ProductRefunded(uint256 indexed id);

    modifier OnlyOwner {
        require(msg.sender == owner);
        _;
    }

    modifier OnlySeller(uint _id) {
        require(msg.sender == products[_id].seller);
        _;
    }

    modifier OnlyBuyer(uint _id){
        require(msg.sender == products[_id].buyer);
        _;
    }

    function listProducts(string calldata _name, uint _price) external {
        require(_price > 0, "Price must be > 0");
        productCount++;
        products[productCount] = Product({
            id: productCount,
            name: _name,
            price: _price,
            seller: payable(msg.sender),
            buyer: address(0),
            status: OrderStatus.Listed
        });

        emit ProductListed(productCount, _name, _price, msg.sender);
    } 

    function buyProduct (uint _id) external payable {
        Product storage product = products[_id];

        require(product.status == OrderStatus.Listed, "Not for sale");
        require(msg.value == product.price, "Incorrect ETH");
        require(msg.sender != product.seller, "Seller cannot buy");

        product.buyer = msg.sender;
        product.status = OrderStatus.Paid;

        emit ProductPaid(_id, msg.sender);
    }

    function markAsShipped(uint _id) external OnlySeller(_id){
        Product storage product = products[_id];
        require(product.status == OrderStatus.Paid, "Not paid yet");
        product.status = OrderStatus.Shipped;
        emit ProductShipped(_id);
    }

    function confirmDelivery(uint _id) external OnlyBuyer(_id) {
        Product storage product = products[_id];
        require(product.status == OrderStatus.Shipped, "Not shipped");
        product.status = OrderStatus.Completed;

        uint256 fee = (product.price * platformFeePercentage) / 100;
        uint256 sellerAmount = product.price - fee;

        payable(owner).transfer(fee);
        product.seller.transfer(sellerAmount);

        emit ProductCompleted(_id);
    }

    function refundBuyer(uint256 _id) external {
        Product storage product = products[_id];

        require(
            msg.sender == product.seller || msg.sender == owner,
            "Not authorized"
        );
        require(product.status == OrderStatus.Paid, "Cannot refund now");

        product.status = OrderStatus.Refunded;
        payable(product.buyer).transfer(product.price);

        emit ProductRefunded(_id);
    }
}