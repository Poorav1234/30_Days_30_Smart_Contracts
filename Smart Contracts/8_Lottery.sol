// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract LotterySimulatedVRF {

    uint public entryFees;
    address public owner;

    enum LotteryState { OPEN, CALCULATING }
    LotteryState public lotteryState;

    struct Player {
        uint id;
        address playerAddress;
    }

    Player[] public players;
    uint private id;
    uint public totalPool;

    address public lastWinner;

    event PlayerRegistered(address player, uint id);
    event WinnerPicked(address winner, uint amount);

    constructor(uint fees) {
        require(fees > 0, "Entry fees must be greater than zero");
        owner = msg.sender;
        entryFees = fees;
        lotteryState = LotteryState.OPEN;
    }

    function register() public payable {
        require(lotteryState == LotteryState.OPEN, "Lottery not open");
        require(msg.value == entryFees, "Send exact entry fee");

        id++;
        totalPool += msg.value;
        players.push(Player(id, msg.sender));

        emit PlayerRegistered(msg.sender, id);
    }

    function getWinner() public {
        require(msg.sender == owner, "Only owner");
        require(players.length > 0, "No players");
        require(lotteryState == LotteryState.OPEN, "Already calculating");

        lotteryState = LotteryState.CALCULATING;

        uint randomNumber = uint(keccak256(abi.encodePacked(block.timestamp, block.difficulty, players.length)));
        fulfillRandomWords(randomNumber);
    }

    function fulfillRandomWords(uint randomNumber) internal {
        uint winnerIndex = randomNumber % players.length;
        address winner = players[winnerIndex].playerAddress;

        lastWinner = winner;

        uint amount = address(this).balance;
        (bool success,) = payable(winner).call{value: amount}("");
        require(success, "ETH Transfer failed");

        delete players;
        id = 0;
        totalPool = 0;
        lotteryState = LotteryState.OPEN;

        emit WinnerPicked(winner, amount);
    }

    function getPlayersLength() public view returns (uint) {
        return players.length;
    }
}
