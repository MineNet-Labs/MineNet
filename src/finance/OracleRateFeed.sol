// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IMineNetRegistry} from "src/access/interfaces/IMineNetRegistry.sol";
import {Actions} from "src/access/libraries/Actions.sol";
import {CurrencyLib} from "src/finance/libraries/CurrencyLib.sol";

/**
 * @title OracleRateFeed
 * @author 0xEmmyb2
 * @notice An exchange-rate feed (USD per one unit of a local currency, e.g. RWF) for currencies that have no
 * Chainlink feed on Base.
 * @dev MineNet oracle nodes post rates from an approved source (e.g. the National Bank of Rwanda reference rate).
 * It implements Chainlink's `AggregatorV3Interface`, so {CurrencyManager} treats it like any other feed and it
 * can be swapped for a Chainlink feed later.
 *
 * Guard rail: if {maxDeviationBps} is set, one update cannot move the rate by more than that, which limits the
 * damage of a faulty or rogue node.
 */
contract OracleRateFeed is AggregatorV3Interface {
    /**
     * @notice One posted rate.
     * @param answer Posted rate, in {decimals} decimals.
     * @param updatedAt When it was posted.
     */
    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    /**
     * @notice Version of this feed implementation (`AggregatorV3Interface`).
     */
    uint256 public constant version = 1;

    /**
     * @notice Participant, role and permission registry.
     */
    IMineNetRegistry public immutable registry;

    /**
     * @notice Decimals of the posted rates (`AggregatorV3Interface`).
     */
    uint8 public immutable decimals;

    /**
     * @notice Human-readable description of the feed, e.g. "RWF / USD" (`AggregatorV3Interface`).
     */
    string public description;

    /**
     * @notice Maximum change between two consecutive rates, in basis points (0 = no limit).
     */
    uint16 public maxDeviationBps;

    /**
     * @dev Id of the latest round (0 = none posted).
     */
    uint80 private _latestRoundId;

    /**
     * @dev Round id => posted rate.
     */
    mapping(uint80 roundId => Round) private _rounds;

    /**
     * @param registry_ Participant, role and permission registry.
     * @param decimals_ Decimals of the posted rates.
     * @param description_ Human-readable description of the feed.
     * @param maxDeviationBps_ Initial maximum deviation, in basis points (0 = no limit).
     */
    constructor(IMineNetRegistry registry_, uint8 decimals_, string memory description_, uint16 maxDeviationBps_) {
        registry = registry_;
        decimals = decimals_;
        description = description_;
        maxDeviationBps = maxDeviationBps_;
    }

    /**
     * @notice Posts the latest rate as a new round.
     * @dev Only an oracle node (`REPORT_READING`). Rejects non-positive answers and, when {maxDeviationBps} is set,
     * answers too far from the previous round.
     * @param answer USD per one unit of the currency, in {decimals} decimals.
     * @custom:emits RatePosted
     */
    function postRate(int256 answer) external {
        if (!registry.isAuthorized(msg.sender, Actions.REPORT_READING)) {
            revert CurrencyLib.OracleRateFeed__Unauthorized(msg.sender);
        }
        if (answer <= 0) revert CurrencyLib.OracleRateFeed__InvalidAnswer(answer);
        int256 previous = _rounds[_latestRoundId].answer;
        if (maxDeviationBps != 0 && previous != 0) {
            int256 diff = answer > previous ? answer - previous : previous - answer;
            if (diff * 10_000 > previous * int256(uint256(maxDeviationBps))) {
                revert CurrencyLib.OracleRateFeed__DeviationTooLarge(previous, answer);
            }
        }
        uint80 roundId = ++_latestRoundId;
        _rounds[roundId] = Round({answer: answer, updatedAt: block.timestamp});
        emit CurrencyLib.RatePosted(roundId, answer, msg.sender);
    }

    /**
     * @notice Sets the maximum change between two consecutive rates.
     * @dev Only a {MineNetRegistry} admin.
     * @param maxDeviationBps_ Maximum deviation, in basis points (0 = no limit).
     * @custom:emits MaxDeviationSet
     */
    function setMaxDeviation(uint16 maxDeviationBps_) external {
        if (!registry.isAdmin(msg.sender)) {
            revert CurrencyLib.CurrencyManager__NotRegistryAdmin(msg.sender);
        }
        maxDeviationBps = maxDeviationBps_;
        emit CurrencyLib.MaxDeviationSet(maxDeviationBps_);
    }

    /**
     * @inheritdoc AggregatorV3Interface
     */
    function getRoundData(uint80 roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        return _roundData(roundId);
    }

    /**
     * @inheritdoc AggregatorV3Interface
     */
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return _roundData(_latestRoundId);
    }

    /**
     * @dev Returns a round in `AggregatorV3Interface` layout, reverting if it has no data.
     * @param roundId Round id.
     * @return roundId The round id.
     * @return answer The posted rate.
     * @return startedAt When it was posted.
     * @return updatedAt When it was posted.
     * @return answeredInRound The round id.
     */
    function _roundData(uint80 roundId) private view returns (uint80, int256, uint256, uint256, uint80) {
        Round memory r = _rounds[roundId];
        if (r.updatedAt == 0) revert CurrencyLib.OracleRateFeed__NoData();
        return (roundId, r.answer, r.updatedAt, r.updatedAt, roundId);
    }
}
