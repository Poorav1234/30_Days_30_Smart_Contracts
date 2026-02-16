// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/* ============================= */
/*        OPENZEPPELIN           */
/* ============================= */

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/* ============================= */
/*        CHAINLINK ORACLE       */
/* ============================= */ 

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        );
}

/* ============================= */
/*        CONTRACT               */
/* ============================= */

contract AdvancedPredictionMarket is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;

    /* ============================= */
    /*        CUSTOM ERRORS          */
    /* ============================= */

    error MarketClosed();
    error MarketAlreadyResolved();
    error NotWinner();
    error InvalidAmount();
    error InvalidOracle();
    error FeeTooHigh();
    error MarketNotEnded();
    error MarketNotResolved();

    /* ============================= */
    /*        ENUM                  */
    /* ============================= */

    enum Outcome {
        Unresolved,
        Yes,
        No,
        Cancelled
    }

    /* ============================= */
    /*        STRUCT (Packed)       */
    /* ============================= */

    struct Market {
        uint128 totalYes;
        uint128 totalNo;
        uint64 deadline;
        uint16 feePercent;
        bool resolved;
        Outcome result;
        address oracle;
        int256 targetPrice;
    }

    /* ============================= */
    /*        STATE VARIABLES        */
    /* ============================= */

    IERC20Upgradeable public token;
    uint256 public marketCount;
    uint16 public constant MAX_FEE = 10;

    mapping(uint256 => Market) public markets;
    mapping(uint256 => mapping(address => uint256)) public yesBets;
    mapping(uint256 => mapping(address => uint256)) public noBets;

    /* ============================= */
    /*        EVENTS                */
    /* ============================= */

    event MarketCreated(uint256 indexed id, int256 targetPrice);
    event BetPlaced(uint256 indexed id, address indexed user, bool side, uint256 amount);
    event MarketResolved(uint256 indexed id, uint8 result);
    event RewardClaimed(uint256 indexed id, address indexed user, uint256 reward);

    /* ============================= */
    /*        INITIALIZER           */
    /* ============================= */

    function initialize(address _token) public initializer {
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        token = IERC20Upgradeable(_token);
    }

    /* ============================= */
    /*        CREATE MARKET         */
    /* ============================= */

    function createMarket(
        uint64 duration,
        uint16 feePercent,
        address oracle,
        int256 targetPrice
    ) external onlyOwner {

        if (feePercent > MAX_FEE) revert FeeTooHigh();
        if (oracle == address(0)) revert InvalidOracle();

        markets[marketCount] = Market({
            totalYes: 0,
            totalNo: 0,
            deadline: uint64(block.timestamp + duration),
            feePercent: feePercent,
            resolved: false,
            result: Outcome.Unresolved,
            oracle: oracle,
            targetPrice: targetPrice
        });

        emit MarketCreated(marketCount, targetPrice);
        marketCount++;
    }

    /* ============================= */
    /*        PLACE BET             */
    /* ============================= */

    function placeBet(
        uint256 marketId,
        bool isYes,
        uint256 amount
    )
        external
        nonReentrant
        whenNotPaused
    {
        Market storage m = markets[marketId];

        if (block.timestamp >= m.deadline) revert MarketClosed();
        if (m.resolved) revert MarketAlreadyResolved();
        if (amount == 0) revert InvalidAmount();

        token.safeTransferFrom(msg.sender, address(this), amount);

        if (isYes) {
            yesBets[marketId][msg.sender] += amount;
            m.totalYes += uint128(amount);
        } else {
            noBets[marketId][msg.sender] += amount;
            m.totalNo += uint128(amount);
        }

        emit BetPlaced(marketId, msg.sender, isYes, amount);
    }

    /* ============================= */
    /*        RESOLVE MARKET        */
    /* ============================= */

    function resolveMarket(uint256 marketId)
        external
        nonReentrant
    {
        Market storage m = markets[marketId];

        if (block.timestamp < m.deadline) revert MarketNotEnded();
        if (m.resolved) revert MarketAlreadyResolved();

        (, int256 price,,,) = AggregatorV3Interface(m.oracle).latestRoundData();

        m.resolved = true;

        if (price >= m.targetPrice) {
            m.result = Outcome.Yes;
        } else {
            m.result = Outcome.No;
        }

        emit MarketResolved(marketId, uint8(m.result));
    }

    /* ============================= */
    /*        CLAIM REWARD          */
    /* ============================= */

    function claimReward(uint256 marketId)
        external
        nonReentrant
    {
        Market storage m = markets[marketId];
        if (!m.resolved) revert MarketNotResolved();

        uint256 userBet;
        uint256 reward;

        if (m.result == Outcome.Yes) {
            userBet = yesBets[marketId][msg.sender];
            if (userBet == 0) revert NotWinner();
            reward = (userBet * (m.totalYes + m.totalNo)) / m.totalYes;
        } else {
            userBet = noBets[marketId][msg.sender];
            if (userBet == 0) revert NotWinner();
            reward = (userBet * (m.totalYes + m.totalNo)) / m.totalNo;
        }

        uint256 fee = (reward * m.feePercent) / 100;
        reward -= fee;

        yesBets[marketId][msg.sender] = 0;
        noBets[marketId][msg.sender] = 0;

        token.safeTransfer(owner(), fee);
        token.safeTransfer(msg.sender, reward);

        emit RewardClaimed(marketId, msg.sender, reward);
    }

    /* ============================= */
    /*        PAUSE CONTROL         */
    /* ============================= */

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ============================= */
    /*        UUPS AUTHORIZE        */
    /* ============================= */

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwner
    {}
}
