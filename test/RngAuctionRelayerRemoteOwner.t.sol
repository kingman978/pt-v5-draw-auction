// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";

import { UD2x18 } from "prb-math/UD2x18.sol";
import { RngAuction } from "../src/RngAuction.sol";
import { IRngAuctionRelayListener } from "../src/interfaces/IRngAuctionRelayListener.sol";
import { AuctionResult } from "../src/interfaces/IAuction.sol";

import { RngRelayerBaseTest } from "./helpers/RngRelayerBaseTest.sol";

import { RngNotCompleted } from "../src/abstract/RngAuctionRelayer.sol";

import {
    RngAuctionRelayerRemoteOwner,
    ISingleMessageDispatcher,
    RemoteOwner,
    RemoteOwnerCallEncoder
} from "../src/RngAuctionRelayerRemoteOwner.sol";

contract RngAuctionRelayerRemoteOwnerTest is RngRelayerBaseTest {

    event RelayedToDispatcher(
        ISingleMessageDispatcher messageDispatcher,
        uint256 indexed remoteOwnerChainId,
        RemoteOwner remoteOwner,
        IRngAuctionRelayListener remoteRngAuctionRelayListener,
        address indexed rewardRecipient,
        bytes32 indexed messageId
    );

    RngAuctionRelayerRemoteOwner relayer;

    ISingleMessageDispatcher messageDispatcher;
    RemoteOwner remoteOwner;
    uint256 remoteOwnerChainId = 1;

    function setUp() public override {
        super.setUp();
        messageDispatcher = ISingleMessageDispatcher(makeAddr("messageDispatcher"));
        remoteOwner = RemoteOwner(makeAddr("remoteOwner"));

        relayer = new RngAuctionRelayerRemoteOwner(
            rngAuction
        );
    }

    function testConstructor() public {
        assertEq(address(relayer.rngAuction()), address(rngAuction));
    }

    function testRelay_happyPath() public {
        mockIsRngComplete(true);
        mockRngResults(123, 456);
        mockAuctionResult(address(this), UD2x18.wrap(0.5 ether));
        mockCurrentSequenceId(789);

        vm.mockCall(
            address(messageDispatcher),
            abi.encodeWithSelector(
                messageDispatcher.dispatchMessage.selector,
                remoteOwnerChainId,
                address(remoteOwner),
                RemoteOwnerCallEncoder.encodeCalldata(
                    address(rngAuctionRelayListener),
                    0,
                    abi.encodeWithSelector(
                        rngAuctionRelayListener.rngComplete.selector,
                        123, 456, address(this), 789, AuctionResult(address(this), UD2x18.wrap(0.5 ether))
                    )
                )
            ),
            abi.encode(bytes32(uint(9999)))
        );

        vm.expectEmit(true, true, false, false);

        emit RelayedToDispatcher(
            messageDispatcher,
            remoteOwnerChainId,
            remoteOwner,
            rngAuctionRelayListener,
            address(this),
            bytes32(uint(9999))
        );
        assertEq(relayer.relay(
            messageDispatcher,
            remoteOwnerChainId,
            remoteOwner,
            rngAuctionRelayListener,
            address(this)
        ), bytes32(uint(9999)));
    }

}
