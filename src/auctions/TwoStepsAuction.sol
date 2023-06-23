// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { Auction } from "src/auctions/Auction.sol";
import { RNGRequestor, RNGInterface } from "src/RNGRequestor.sol";

contract TwoStepsAuction is Auction, RNGRequestor {
  /* ============ Constructor ============ */

  /**
   * @notice Contract constructor.
   * @param rng_ Address of the RNG service
   * @param rngTimeout_ Time in seconds before an RNG request can be cancelled
   * @param _auctionPhases Number of auction phases
   * @param auctionDuration_ Duration of the auction in seconds
   * @param _owner Address of the DrawAuction owner
   */
  constructor(
    RNGInterface rng_,
    uint32 rngTimeout_,
    uint8 _auctionPhases,
    uint32 auctionDuration_,
    address _owner
  ) Auction(_auctionPhases, auctionDuration_) RNGRequestor(rng_, rngTimeout_, _owner) {}

  /* ============ Internal Functions ============ */

  /* ============ Hooks ============ */

  /**
   * @notice Hook called after the RNG request has started.
   * @dev The auction is not aware of the PrizePool contract, so startTime is set to 0.
   *      Since the first phase of the auction starts when the draw has ended,
   *      we can derive the actual startTime by calling PrizePool.nextDrawEndsAt() when computing the reward.
   * @param _rewardRecipient Address that will receive the auction reward for starting the RNG request
   */
  function _afterRNGStart(address _rewardRecipient) internal override {
    _setPhase(0, 0, uint64(block.timestamp), _rewardRecipient);
    emit AuctionPhaseCompleted(0, msg.sender);
  }

  /**
   * @notice Hook called after the RNG request has completed.
   * @param _randomNumber The random number that was generated
   * @param _rewardRecipient Address that will receive the auction reward for completing the RNG request
   */
  function _afterRNGComplete(uint256 _randomNumber, address _rewardRecipient) internal override {
    _setPhase(1, _getPhase(0).endTime, uint64(block.timestamp), _rewardRecipient);
    emit AuctionPhaseCompleted(1, msg.sender);

    _afterAuctionEnds(_randomNumber);
  }
}
