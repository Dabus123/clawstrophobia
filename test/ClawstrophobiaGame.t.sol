// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../contracts/ClawstrophobiaToken.sol";
import "../contracts/ClawstrophobiaGame.sol";

contract ClawstrophobiaGameTest is Test {
    ClawstrophobiaToken public token;
    ClawstrophobiaGame public game;

    address public owner;
    address public dev;
    address public alice;
    address public bob;

    uint256 constant ENTRY = 10_000 * 1e18;
    uint256 constant MOVE_COST = 0.001 ether;
    uint256 constant ROUND_DURATION = 15 minutes;

    function setUp() public {
        owner = address(this);
        dev = makeAddr("dev");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        token = new ClawstrophobiaToken();
        game = new ClawstrophobiaGame(address(token), dev);

        token.transfer(alice, 100_000 * 1e18);
        token.transfer(bob, 100_000 * 1e18);
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function test_EnterAndPlayable() public {
        vm.startPrank(alice);
        token.approve(address(game), ENTRY);
        game.enter(50, 50);
        vm.stopPrank();

        (uint256 x, uint256 y, bool onBoard) = game.getAgentPosition(alice);
        assertTrue(onBoard);
        assertEq(x, 50);
        assertEq(y, 50);
        assertEq(game.getAgentAt(50, 50), alice);
        assertTrue(game.isPlayable(50, 50));
    }

    function test_OneAgentPerCell() public {
        vm.startPrank(alice);
        token.approve(address(game), ENTRY);
        game.enter(50, 50);
        vm.stopPrank();

        vm.startPrank(bob);
        token.approve(address(game), ENTRY);
        vm.expectRevert("cell occupied");
        game.enter(50, 50);
        vm.stopPrank();
    }

    function test_Move() public {
        vm.prank(alice);
        token.approve(address(game), ENTRY);
        vm.prank(alice);
        game.enter(50, 50);

        vm.prank(alice);
        game.move{value: MOVE_COST}(51, 50);

        (uint256 x, uint256 y,) = game.getAgentPosition(alice);
        assertEq(x, 51);
        assertEq(y, 50);
        assertEq(game.getAgentAt(50, 50), address(0));
        assertEq(game.getAgentAt(51, 50), alice);
    }

    function test_MoveRequiresEth() public {
        vm.prank(alice);
        token.approve(address(game), ENTRY);
        vm.prank(alice);
        game.enter(50, 50);

        vm.prank(alice);
        vm.expectRevert("need 0.001 ETH");
        game.move{value: 0}(51, 50);
    }

    function test_AdvanceRoundShrinksBounds() public {
        (uint256 minX, uint256 maxX, uint256 minY, uint256 maxY) = game.getPlayableBounds();
        assertEq(maxX - minX, 99);
        assertEq(maxY - minY, 99);

        vm.warp(block.timestamp + ROUND_DURATION);
        game.advanceRound();

        (minX, maxX, minY, maxY) = game.getPlayableBounds();
        // One edge removed: one dimension shrunk by 1 (e.g. 99x100 or 100x99)
        assertTrue((maxX - minX == 98 && maxY - minY == 99) || (maxX - minX == 99 && maxY - minY == 98), "bounds should shrink");
    }

    function test_ResolutionSplits50_40_10() public {
        vm.prank(alice);
        token.approve(address(game), ENTRY);
        vm.prank(alice);
        game.enter(50, 50);
        vm.prank(alice);
        game.move{value: MOVE_COST}(51, 50);
        vm.prank(alice);
        game.move{value: MOVE_COST}(50, 50);

        uint256 ethPoolWas = 2 * MOVE_COST;
        uint256 tokenPoolWas = ENTRY;

        // Shrink to 1x1 (deterministic given vm.warp)
        for (uint256 i = 0; i < 198; i++) {
            vm.warp(block.timestamp + ROUND_DURATION);
            (uint256 mx, uint256 Mx, uint256 my, uint256 My) = game.getPlayableBounds();
            if (mx == Mx && my == My) break;
            game.advanceRound();
        }

        uint256 devEthBefore = dev.balance;
        uint256 devTokenBefore = token.balanceOf(dev);

        vm.warp(block.timestamp + ROUND_DURATION);
        game.advanceRound();

        uint256 devShareEth = (ethPoolWas * 4000) / 10_000;
        uint256 devShareTok = (tokenPoolWas * 4000) / 10_000;

        assertEq(dev.balance - devEthBefore, devShareEth, "dev gets 40% ETH");
        assertEq(token.balanceOf(dev) - devTokenBefore, devShareTok, "dev gets 40% token");
        // Winner: 10% retained. Rollover (no one on final cell): 60% retained (50% + 10%)
        uint256 ethRetained = game.ethPool();
        uint256 tokenRetained = game.tokenPool();
        assertTrue(ethRetained == (ethPoolWas * 1000) / 10_000 || ethRetained == (ethPoolWas * 6000) / 10_000, "10% or 60% ETH retained");
        assertTrue(tokenRetained == (tokenPoolWas * 1000) / 10_000 || tokenRetained == (tokenPoolWas * 6000) / 10_000, "10% or 60% token retained");
    }

    function test_DevGets40PercentRetained10Percent() public {
        vm.prank(alice);
        token.approve(address(game), ENTRY);
        vm.prank(alice);
        game.enter(50, 50);
        vm.prank(alice);
        game.move{value: MOVE_COST}(51, 50);

        for (uint256 i = 0; i < 198; i++) {
            vm.warp(block.timestamp + ROUND_DURATION);
            (uint256 mx, uint256 Mx, uint256 my, uint256 My) = game.getPlayableBounds();
            if (mx == Mx && my == My) break;
            game.advanceRound();
        }

        uint256 ethPoolBefore = game.ethPool();
        uint256 tokenPoolBefore = game.tokenPool();
        uint256 devEthBefore = dev.balance;
        uint256 devTokBefore = token.balanceOf(dev);

        vm.warp(block.timestamp + ROUND_DURATION);
        game.advanceRound();

        assertEq(dev.balance - devEthBefore, (ethPoolBefore * 4000) / 10_000, "dev gets 40% ETH");
        assertEq(token.balanceOf(dev) - devTokBefore, (tokenPoolBefore * 4000) / 10_000, "dev gets 40% token");
        // 10% always retained; if no winner, 50% also stays (60% total). If winner, 10% stays.
        uint256 ethRetained = game.ethPool();
        uint256 tokenRetained = game.tokenPool();
        assertTrue(ethRetained == (ethPoolBefore * 1000) / 10_000 || ethRetained == (ethPoolBefore * 6000) / 10_000, "10% or 60% ETH retained");
        assertTrue(tokenRetained == (tokenPoolBefore * 1000) / 10_000 || tokenRetained == (tokenPoolBefore * 6000) / 10_000, "10% or 60% token retained");
    }

    function test_IsDangerBoundary() public {
        assertTrue(game.isDanger(0, 0));
        assertTrue(game.isDanger(99, 99));
        assertTrue(game.isDanger(50, 0));
        assertFalse(game.isDanger(50, 50)); // center is not on boundary when 100x100
    }

    function test_SetDevAddress() public {
        address newDev = makeAddr("newDev");
        game.setDevAddress(newDev);
        assertEq(game.devAddress(), newDev);
    }
}
