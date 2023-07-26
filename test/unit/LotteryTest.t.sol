// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import {DeployLottery} from "../../script/DeployLottery.s.sol";
import {Lottery} from "../../src/Lottery.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {StdCheats} from "forge-std/StdCheats.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract LotteryTest is StdCheats, Test {
    Lottery lottery;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;

    address public PLAYER = makeAddr("player");
    uint256 public constant STARTING_USER_BALANCE = 10 ether;

    /**
     * Events
     */
    event EnteredLottery(address indexed player);

    /**
     * Modifiers
     */
    modifier lotteryEnteredAndTimePassed() {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function setUp() external {
        DeployLottery deployer = new DeployLottery();
        (lottery, helperConfig) = deployer.run();
        (entranceFee, interval, vrfCoordinator, gasLane, subscriptionId, callbackGasLimit,,) =
            helperConfig.activeNetworkConfig();
        vm.deal(PLAYER, STARTING_USER_BALANCE); // Give player some ETH
    }

    function testLotteryInitializesInOpenState() public view {
        assert(lottery.getLotteryState() == Lottery.LotteryState.OPEN);
    }

    /**
     * enterLottery()
     */
    function testLotteryRevertWhenYouDontPayEnough() public {
        vm.prank(PLAYER);
        vm.expectRevert(Lottery.Lottery__NotEnoughEthSend.selector);
        lottery.enterLottery();
    }

    function testLotteryRecordsPlayerWhenTheyEnter() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
        address playerRecorded = lottery.getPlayer(0);
        assert(playerRecorded == PLAYER);
    }

    function testEmitsEventOnEntrance() public {
        vm.prank(PLAYER);
        vm.expectEmit(true, false, false, false, address(lottery));
        emit EnteredLottery(PLAYER);
        lottery.enterLottery{value: entranceFee}();
    }

    function testCantEnterWhenLotteryIsCalculating() public lotteryEnteredAndTimePassed {
        lottery.performUpkeep("");

        vm.expectRevert(Lottery.Lottery__LotteryNotOpen.selector);
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();
    }

    /**
     * checkUpkeep()
     */
    function testCheckUpkeepReturnsFalseIfItHasNoBalance() public {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfLotteryNotOpen() public lotteryEnteredAndTimePassed {
        lottery.performUpkeep("");

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsFalseIfEnoughTimeHasntPassed() public {
        vm.prank(PLAYER);
        lottery.enterLottery{value: entranceFee}();

        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assert(!upkeepNeeded);
    }

    function testCheckUpkeepReturnsTrueWhenParametersGood() public lotteryEnteredAndTimePassed {
        (bool upkeepNeeded,) = lottery.checkUpkeep("");
        assert(upkeepNeeded);
    }

    /**
     * performUpkeep()
     */
    function testPerformUpkeepCanOnlyRunIfCheckUpkeepIsTrue() public lotteryEnteredAndTimePassed {
        lottery.performUpkeep("");
    }

    function testPerformUpkeepRevertsIfCheckUpkeepIsFalse() public {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 lotteryState = 0;

        vm.expectRevert(
            abi.encodeWithSelector(Lottery.Lottery__UpkeepNotNeeded.selector, currentBalance, numPlayers, lotteryState)
        );
        lottery.performUpkeep("");
    }

    function testPerformUpkeepUpdatesLotteryStateAndEmitsRequestId() public lotteryEnteredAndTimePassed {
        vm.recordLogs();
        lottery.performUpkeep(""); //* Emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        Lottery.LotteryState lotteryState = lottery.getLotteryState();

        assert(uint256(requestId) > 0);
        assert(uint256(lotteryState) == 1);
    }

    /**
     * fulfillRandomWords()
     */

    /* Fuzz test with randomRequestId */
    function testFulfillRandomWordsCanOnlyBeCalledAfterPerformUpkeep(uint256 randomRequestId)
        public
        lotteryEnteredAndTimePassed
        skipFork
    {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(randomRequestId, address(lottery));
    }

    function testFulfilRandomWordsPicksAWinnerResetsAndSendsMoney() public lotteryEnteredAndTimePassed skipFork {
        uint256 additionalEntrants = 5;
        uint256 startingIndex = 1;
        for (uint256 i = startingIndex; i < startingIndex + additionalEntrants; i++) {
            address player = address(uint160(i));
            hoax(player, STARTING_USER_BALANCE);
            lottery.enterLottery{value: entranceFee}();
        }

        uint256 prize = entranceFee * (additionalEntrants + 1);

        vm.recordLogs();
        lottery.performUpkeep(""); //* Emit requestId
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        uint256 previousTimestamp = lottery.getLastTimeStamp();

        //* Pretend to be chainlinkVRF to get random number & pick winner
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(uint256(requestId), address(lottery));

        assert(uint256(lottery.getLotteryState()) == 0);
        assert(lottery.getRecentWinner() != address(0));
        assert(lottery.getPlayers().length == 0);
        assert(previousTimestamp < lottery.getLastTimeStamp());
        assert(lottery.getRecentWinner().balance == STARTING_USER_BALANCE + prize - entranceFee);
    }
}
