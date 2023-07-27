// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import { RNGInterface } from "rng/RNGInterface.sol";
import { UD2x18 } from "prb-math/UD2x18.sol";
import { UD60x18, toUD60x18 } from "prb-math/UD60x18.sol";

import { RewardLib } from "local-draw-auction/libraries/RewardLib.sol";
import { StartRngAuction } from "local-draw-auction/StartRngAuction.sol";
import { IAuction, AuctionResults } from "local-draw-auction/interfaces/IAuction.sol";

/**
 * @title   PoolTogether V5 DrawAuction
 * @author  Generation Software Team
 * @notice  The DrawAuction uses an auction mechanism to incentivize the completion of the Draw.
 *          There is a draw auction for each prize pool. The draw auction starts when the new
 *          random number is available for the current draw.
 * @dev     This contract runs synchronously with the StartRngAuction contract, waiting till the RNG
 *          auction is complete and the random number is available before starting the draw
 *          auction.
 */
abstract contract DrawAuction is IAuction {
  /* ============ Constants ============ */

  /// @notice The RNG Auction to get the random number from
  StartRngAuction public immutable rngAuction;

  /* ============ Variables ============ */

  /// @notice The sequence ID that was used in the last auction
  uint32 internal _lastSequenceId;

  /// @notice The auction duration in seconds
  uint64 internal _auctionDurationSeconds;

  /// @notice The target time to complete the auction as a fraction of the auction duration
  UD2x18 internal _auctionTargetTimeFraction;

  /// @notice The last completed auction results
  AuctionResults internal _auctionResults;

  /* ============ Custom Errors ============ */

  /// @notice Thrown if the auction period is zero.
  error AuctionDurationZero();

  /// @notice Thrown if the auction target time is zero.
  error AuctionTargetTimeZero();

  /**
   * @notice Thrown if the auction target time exceeds the auction duration.
   * @param auctionTargetTime The auction target time to complete in seconds
   * @param auctionDuration The auction duration in seconds
   */
  error AuctionTargetTimeExceedsDuration(uint64 auctionTargetTime, uint64 auctionDuration);

  /// @notice Thrown if the StartRngAuction address is the zero address.
  error StartRngAuctionZeroAddress();

  /// @notice Thrown if the current draw auction has already been completed.
  error DrawAlreadyCompleted();

  /// @notice Thrown if the current draw auction has expired.
  error DrawAuctionExpired();

  /// @notice Thrown if the RNG request is not complete for the current sequence.
  error RngNotCompleted();

  /* ============ Constructor ============ */

  /**
   * @notice Deploy the DrawAuction smart contract.
   * @param rngAuction_ The StartRngAuction to get the random number from
   * @param auctionDurationSeconds_ Auction duration in seconds
   * @param auctionTargetTime_ Target time to complete the auction in seconds
   */
  constructor(StartRngAuction rngAuction_, uint64 auctionDurationSeconds_, uint64 auctionTargetTime_) {
    if (address(rngAuction_) == address(0)) revert StartRngAuctionZeroAddress();
    if (auctionDurationSeconds_ == 0) revert AuctionDurationZero();
    if (auctionTargetTime_ == 0) revert AuctionTargetTimeZero();
    if (auctionTargetTime_ > auctionDurationSeconds_) {
      revert AuctionTargetTimeExceedsDuration(auctionTargetTime_, auctionDurationSeconds_);
    }
    rngAuction = rngAuction_;
    _auctionDurationSeconds = auctionDurationSeconds_;
    _auctionTargetTimeFraction = UD2x18.wrap(
      uint64(toUD60x18(auctionTargetTime_).div(toUD60x18(_auctionDurationSeconds)).unwrap())
    );
  }

  /* ============ External Functions ============ */

  /**
   * @notice Completes the current draw with the random number from the StartRngAuction.
   * @dev Requires that the RNG is complete and that the current auction is open.
   * @param _rewardRecipient The address to send the reward to
   */
  function completeDraw(address _rewardRecipient) external {
    if (!rngAuction.isRngComplete()) revert RngNotCompleted();
    if (_isAuctionComplete()) revert DrawAlreadyCompleted();

    (
      StartRngAuction.RngRequest memory _rngRequest,
      uint256 _randomNumber,
      uint64 _rngCompletedAt
    ) = rngAuction.getRngResults();

    uint64 _auctionElapsedSeconds = uint64(block.timestamp) - _rngCompletedAt;
    if (_auctionElapsedSeconds > _auctionDurationSeconds) revert DrawAuctionExpired();

    // Calculate the reward fraction and set the draw auction results
    UD2x18 _reward = _fractionalReward(_auctionElapsedSeconds);
    _auctionResults.recipient = _rewardRecipient;
    _auctionResults.rewardFraction = _reward;
    _lastSequenceId = _rngRequest.sequenceId;

    // Hook after draw auction is complete
    _afterDrawAuction(_randomNumber);

    emit AuctionCompleted(
      _rewardRecipient,
      _rngRequest.sequenceId,
      _auctionElapsedSeconds,
      _reward
    );
  }

  /* ============ IAuction Functions ============ */

  /**
   * @inheritdoc IAuction
   */
  function isAuctionComplete() external view returns (bool) {
    return _isAuctionComplete();
  }

  /**
   * @inheritdoc IAuction
   */
  function isAuctionOpen() external view returns (bool) {
    return
      rngAuction.isRngComplete() &&
      !_isAuctionComplete() &&
      elapsedTime() <= _auctionDurationSeconds;
  }

  /**
   * @inheritdoc IAuction
   */
  function elapsedTime() public view returns (uint64) {
    return uint64(block.timestamp) - rngAuction.rngCompletedAt();
  }

  /**
   * @inheritdoc IAuction
   */
  function auctionDuration() external view returns (uint64) {
    return _auctionDurationSeconds;
  }

  /**
   * @inheritdoc IAuction
   */
  function currentFractionalReward() external view returns (UD2x18) {
    return _fractionalReward(elapsedTime());
  }

  /**
   * @inheritdoc IAuction
   */
  function currentRewardAmount(uint256 _reserve) external view returns (uint256) {
    AuctionResults[] memory _results = new AuctionResults[](2);
    (_results[0], ) = rngAuction.getAuctionResults();
    _results[1] = AuctionResults(msg.sender, _fractionalReward(elapsedTime()));
    return RewardLib.rewards(_results, _reserve)[1];
  }

  /**
   * @inheritdoc IAuction
   */
  function getAuctionResults()
    external
    view
    returns (AuctionResults memory auctionResults, uint32 sequenceId)
  {
    return (_auctionResults, _lastSequenceId);
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Calculates if the current auction is complete.
   * @dev The auction is complete when the last recorded auction sequence ID matches the current sequence ID
   * @return True if the auction is complete, false otherwise
   */
  function _isAuctionComplete() internal view returns (bool) {
    return _lastSequenceId == rngAuction.currentSequenceId();
  }

  /**
   * @notice Calculates the reward fraction for an auction if it were to be completed after the elapsed time.
   * @dev Uses the last sold fraction as the target price for this auction.
   * @return The reward fraction as a UD2x18 value
   */
  function _fractionalReward(uint64 _elapsedSeconds) internal view returns (UD2x18) {
    return
      RewardLib.fractionalReward(
        _elapsedSeconds,
        _auctionDurationSeconds,
        _auctionTargetTimeFraction,
        _auctionResults.rewardFraction
      );
  }

  /* ============ Hooks ============ */

  /**
   * @notice Hook called after the draw auction is completed.
   * @param _randomNumber The random number from the auction
   * @dev Override this in a parent contract to send the random number the DrawManager or
   * to start more auctions if needed.
   */
  function _afterDrawAuction(uint256 _randomNumber) internal virtual {}
}
