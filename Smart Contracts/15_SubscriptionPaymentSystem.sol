// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SubscriptionPayment is ReentrancyGuard, Ownable {

    IERC20 public paymentToken;
    uint256 public planCount;

    struct Plan {
        uint256 price;        
        uint256 duration;     
        bool active;
    }

    struct Subscription {
        uint256 planId;
        uint256 startTime;
        uint256 nextPayment;
        bool active;
    }

    mapping(uint256 => Plan) public plans;
    mapping(address => Subscription) public subscriptions;

    event PlanCreated(uint256 indexed planId, uint256 price, uint256 duration);
    event Subscribed(address indexed user, uint256 indexed planId);
    event PaymentProcessed(address indexed user, uint256 amount);
    event SubscriptionCancelled(address indexed user);

    constructor(address _paymentToken) Ownable(msg.sender) {
        require(_paymentToken != address(0), "Invalid token address");
        paymentToken = IERC20(_paymentToken);
    }

    function createPlan(
        uint256 _price,
        uint256 _duration
    ) external onlyOwner {
        require(_price > 0, "Price must be > 0");
        require(_duration > 0, "Duration must be > 0");

        plans[planCount] = Plan({
            price: _price,
            duration: _duration,
            active: true
        });

        emit PlanCreated(planCount, _price, _duration);
        planCount++;
    }

    function deactivatePlan(uint256 _planId) external onlyOwner {
        require(_planId < planCount, "Invalid plan");
        plans[_planId].active = false;
    }


    function subscribe(uint256 _planId) external nonReentrant {
        require(_planId < planCount, "Invalid plan");

        Plan memory plan = plans[_planId];
        require(plan.active, "Plan inactive");

        require(
            paymentToken.transferFrom(msg.sender, owner(), plan.price),
            "Initial payment failed"
        );

        subscriptions[msg.sender] = Subscription({
            planId: _planId,
            startTime: block.timestamp,
            nextPayment: block.timestamp + plan.duration,
            active: true
        });

        emit Subscribed(msg.sender, _planId);
    }

    function processPayment(address _user) public nonReentrant {
        Subscription storage sub = subscriptions[_user];
        require(sub.active, "Subscription inactive");
        require(block.timestamp >= sub.nextPayment, "Payment not due");

        Plan memory plan = plans[sub.planId];
        require(plan.active, "Plan inactive");

        require(
            paymentToken.transferFrom(_user, owner(), plan.price),
            "Payment failed"
        );

        sub.nextPayment += plan.duration;

        emit PaymentProcessed(_user, plan.price);
    }

    function cancelSubscription() external {
        Subscription storage sub = subscriptions[msg.sender];
        require(sub.active, "No active subscription");

        sub.active = false;

        emit SubscriptionCancelled(msg.sender);
    }

    function isPaymentDue(address _user) external view returns (bool) {
        Subscription memory sub = subscriptions[_user];
        if (!sub.active) return false;
        return block.timestamp >= sub.nextPayment;
    }

    function getSubscription(address _user)
        external
        view
        returns (
            uint256 planId,
            uint256 startTime,
            uint256 nextPayment,
            bool active
        )
    {
        Subscription memory sub = subscriptions[_user];
        return (
            sub.planId,
            sub.startTime,
            sub.nextPayment,
            sub.active
        );
    }
}
