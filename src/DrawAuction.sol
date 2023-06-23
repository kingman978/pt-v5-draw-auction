// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.17;

import { PrizePool } from "v5-prize-pool/PrizePool.sol";

import { Auction, AuctionLib } from "src/auctions/Auction.sol";
import { TwoStepsAuction, RNGInterface } from "src/auctions/TwoStepsAuction.sol";
import { RewardLib } from "src/libraries/RewardLib.sol";

/**
 * @title PoolTogether V5 DrawAuction
 * @author PoolTogether Inc. Team
 * @notice The DrawAuction uses an auction mechanism to incentivize the completion of the Draw.
 *         This mechanism relies on a linear interpolation to incentivizes anyone to start and complete the Draw.
 *         The first user to complete the Draw gets rewarded with the partial or full PrizePool reserve amount.
 */
contract DrawAuction is TwoStepsAuction {
  /* ============ Variables ============ */

  /// @notice Instance of the PrizePool to compute Draw for.
  PrizePool internal immutable _prizePool;

  /* ============ Custom Errors ============ */

  /// @notice Thrown when the PrizePool address passed to the constructor is zero address.
  error PrizePoolNotZeroAddress();

  /* ============ Constructor ============ */

  /**
   * @notice Contract constructor.
   * @param rng_ Address of the RNG service
   * @param rngTimeout_ Time in seconds before an RNG request can be cancelled
   * @param prizePool_ Address of the prize pool
   * @param _auctionPhases Number of auction phases
   * @param auctionDuration_ Duration of the auction in seconds
   * @param _owner Address of the DrawAuction owner
   */
  constructor(
    RNGInterface rng_,
    uint32 rngTimeout_,
    PrizePool prizePool_,
    uint8 _auctionPhases,
    uint32 auctionDuration_,
    address _owner
  ) TwoStepsAuction(rng_, rngTimeout_, _auctionPhases, auctionDuration_, _owner) {
    if (address(prizePool_) == address(0)) revert PrizePoolNotZeroAddress();
    _prizePool = prizePool_;
  }

  /* ============ External Functions ============ */

  /* ============ Getter Functions ============ */

  /**
   * @notice Prize Pool instance for which the Draw is triggered.
   * @return Prize Pool instance
   */
  function prizePool() external view returns (PrizePool) {
    return _prizePool;
  }

  /**
   * @notice Reward for completing the Auction phase.
   * @param _phase Phase to get reward for
   * @return Reward amount
   */
  function reward(AuctionLib.Phase calldata _phase) external view returns (uint256) {
    return RewardLib.reward(_phase, _prizePool, _auctionDuration);
  }

  /* ============ Internal Functions ============ */

  /* ============ Hooks ============ */

  /**
   * @notice Hook called after the auction has ended.
   * @param _randomNumber The random number that was generated
   */
  function _afterAuctionEnds(uint256 _randomNumber) internal override {
    AuctionLib.Phase memory _startRNGPhase = _getPhase(0);
    AuctionLib.Phase memory _completeRNGPhase = _getPhase(1);

    AuctionLib.Phase[] memory _auctionPhases = new AuctionLib.Phase[](2);
    _auctionPhases[0] = _startRNGPhase;
    _auctionPhases[1] = _completeRNGPhase;

    uint256[] memory _rewards = RewardLib.rewards(_auctionPhases, _prizePool, _auctionDuration);

    _prizePool.completeAndStartNextDraw(_randomNumber);

    if (_startRNGPhase.recipient == _completeRNGPhase.recipient) {
      _prizePool.withdrawReserve(_startRNGPhase.recipient, uint104(_rewards[0] + _rewards[1]));
    } else {
      _prizePool.withdrawReserve(_startRNGPhase.recipient, uint104(_rewards[0]));
      _prizePool.withdrawReserve(_completeRNGPhase.recipient, uint104(_rewards[1]));
    }

    uint8[] memory _phaseIds = new uint8[](2);
    _phaseIds[0] = _startRNGPhase.id;
    _phaseIds[1] = _completeRNGPhase.id;

    address[] memory _rewardRecipients = new address[](2);
    _rewardRecipients[0] = _startRNGPhase.recipient;
    _rewardRecipients[1] = _completeRNGPhase.recipient;

    emit AuctionRewardsDistributed(_phaseIds, _rewardRecipients, _rewards);
  }
}
