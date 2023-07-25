// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions

/**
 * @title Lottery Contract
 * @author Jamie Anderson
 * @notice This contract is used to create and run a lottery
 * @dev This contract implements Chainlink VRF to generate random numbers
 * and Chainlink automation to run the lottery
 */
contract Lottery {
    /**
     * Errors
     */
    error Lottery__NotEnoughEthSend();

    /**
     * State variables
     */
    uint256 private immutable i_entranceFee;

    address payable[] private s_players;

    /**
     * Events
     */
    event EnteredLottery(address indexed player);

    constructor(uint256 entranceFee) {
        i_entranceFee = entranceFee;
    }

    function enterLottery() external payable {
        if (msg.value < i_entranceFee) {
            revert Lottery__NotEnoughEthSend();
        }
        s_players.push(payable(msg.sender));
        emit EnteredLottery(msg.sender);
    }

    function pickWinner() public {}

    /**
     * External & public view & pure functions
     */
    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }
}
