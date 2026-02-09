// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract PriceFeedConsumer {

    AggregatorV3Interface public priceFeed;

    constructor(address _priceFeedAddress) {
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
    }

    function getLatestPrice() public view returns (int256) {
        (
            , 
            int256 price, 
            , 
            uint256 updatedAt, 
            
        ) = priceFeed.latestRoundData();

        require(updatedAt > 0, "Invalid price data");
        return price;
    }

    function getDecimals() public view returns (uint8) {
        return priceFeed.decimals();
    }

    function getLastUpdatedTime() public view returns (uint256) {
        (, , , uint256 updatedAt, ) = priceFeed.latestRoundData();
        return updatedAt;
    }

    function getReadablePrice() public view returns (int256) {
        int256 price = getLatestPrice();
        uint8 decimals = getDecimals();

        return price / int256(10 ** decimals);
    }
}
