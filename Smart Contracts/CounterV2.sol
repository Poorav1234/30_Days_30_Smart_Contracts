// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./CounterV1.sol";

contract CounterV2 is CounterV1 {

    function decrement() public {
        require(count > 0, "Already zero");
        count -= 1;
    }
}
