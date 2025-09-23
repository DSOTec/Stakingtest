// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import  "forge-std/Test.sol";
import {StakingRewards, IERC20} from "./../src/Staking.sol";
import {MockERC20} from "./MockERC20.sol";

contract StakingTest is Test {
    StakingRewards staking;
    MockERC20 stakingToken;
    MockERC20 rewardToken;

    address owner = makeAddr("owner");
    address bob = makeAddr("bob");
    address dso = makeAddr("dso");

    function setUp() public {
        vm.startPrank(owner);
        stakingToken = new MockERC20();
        rewardToken = new MockERC20();
        staking = new StakingRewards(address(stakingToken), address(rewardToken));
        vm.stopPrank();
    }

    function test_alwaysPass() public {
        assertEq(staking.owner(), owner, "Wrong owner set");
        assertEq(address(staking.stakingToken()), address(stakingToken), "Wrong staking token address");
        assertEq(address(staking.rewardsToken()), address(rewardToken), "Wrong reward token address");

        assertTrue(true);
    }

    function test_cannot_stake_amount0() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);

        // we are expecting a revert if we deposit/stake zero
        vm.expectRevert("amount = 0");
        staking.stake(0);
        vm.stopPrank();
    }

    function test_can_stake_successfully() public {
        deal(address(stakingToken), bob, 10e18);
        // start prank to assume user is making subsequent calls
        vm.startPrank(bob);
        IERC20(address(stakingToken)).approve(address(staking), type(uint256).max);
        uint256 _totalSupplyBeforeStaking = staking.totalSupply();
        staking.stake(5e18);
        assertEq(staking.balanceOf(bob), 5e18, "Amounts do not match");
        assertEq(staking.totalSupply(), _totalSupplyBeforeStaking + 5e18, "totalsupply didnt update correctly");
    }

    function  test_cannot_withdraw_amount0() public {
        vm.prank(bob);
        vm.expectRevert("amount = 0");
        staking.withdraw(0);
    }

    function test_can_withdraw_deposited_amount() public {
        test_can_stake_successfully();

        uint256 userStakebefore = staking.balanceOf(bob);
        uint256 totalSupplyBefore = staking.totalSupply();
        staking.withdraw(2e18);
        assertEq(staking.balanceOf(bob), userStakebefore - 2e18, "Balance didnt update correctly");
        assertLt(staking.totalSupply(), totalSupplyBefore, "total supply didnt update correctly");

    }

    function test_notify_Rewards() public {
        // check that it reverts if non owner tried to set duration
        vm.expectRevert("not authorized");
        staking.setRewardsDuration(1 weeks);

        // simulate owner calls setReward successfully
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);
        assertEq(staking.duration(), 1 weeks, "duration not updated correctly");
        // log block.timestamp
        console.log("current time", block.timestamp);
        // move time foward 
        vm.warp(block.timestamp + 200);
        // notify rewards 
        deal(address(rewardToken), owner, 100 ether);
        vm.startPrank(owner); 
        IERC20(address(rewardToken)).transfer(address(staking), 100 ether);
        
        // trigger revert
        vm.expectRevert("reward rate = 0");
        staking.notifyRewardAmount(1);
    
        // trigger second revert
        vm.expectRevert("reward amount > balance");
        staking.notifyRewardAmount(200 ether);

        // trigger first type of flow success
        staking.notifyRewardAmount(100 ether);
        assertEq(staking.rewardRate(), uint256(100 ether)/uint256(1 weeks));
        assertEq(staking.finishAt(), uint256(block.timestamp) + uint256(1 weeks));
        assertEq(staking.updatedAt(), block.timestamp);
    
        // trigger setRewards distribution revert
        vm.expectRevert("reward duration not finished");
        staking.setRewardsDuration(1 weeks);
  }

    function test_lastTimeRewardApplicable() public {
        // Set reward duration
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);

        // Setup rewards
        deal(address(rewardToken), owner, 100 ether);
        rewardToken.transfer(address(staking), 100 ether);
        
        // Test when current time is before finishAt
        staking.notifyRewardAmount(100 ether);
        vm.stopPrank();
        
        uint256 currentTime = block.timestamp;
        assertEq(staking.lastTimeRewardApplicable(), currentTime, "Should return current time when before finishAt");

        // Test when current time is after finishAt
        vm.warp(block.timestamp + 2 weeks);
        assertEq(staking.lastTimeRewardApplicable(), staking.finishAt(), "Should return finishAt when current time > finishAt");
    }

    function test_rewardPerToken() public {
        // Test when no tokens are staked
        assertEq(staking.rewardPerToken(), staking.rewardPerTokenStored(), "Should return rewardPerTokenStored when totalSupply = 0");

        // Setup staking and rewards
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(stakingToken), bob, 100 ether);
        deal(address(rewardToken), address(staking), 70 ether);

        // Bob stakes tokens
        vm.startPrank(bob);
        stakingToken.approve(address(staking), 50 ether);
        staking.stake(50 ether);
        vm.stopPrank();

        // Owner notifies reward
        vm.prank(owner);
        staking.notifyRewardAmount(70 ether);

        // Move time forward
        vm.warp(block.timestamp + 1 days);

        // Calculate expected reward per token
        uint256 timePassed = 1 days;
        uint256 rewardRate = staking.rewardRate();
        uint256 expectedReward = (rewardRate * timePassed * 1e18) / staking.totalSupply();
        
        assertEq(
            staking.rewardPerToken() - staking.rewardPerTokenStored(),
            expectedReward,
            "Reward per token calculation incorrect"
        );
    }

    function test_earned() public {
        // Test when user has not staked
        assertEq(staking.earned(bob), 0, "Should return 0 for non-staker");

        // Setup staking and rewards
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(stakingToken), bob, 100 ether);
        deal(address(rewardToken), address(staking), 70 ether);

        // Bob stakes tokens
        vm.startPrank(bob);
        stakingToken.approve(address(staking), 50 ether);
        staking.stake(50 ether);
        vm.stopPrank();

        // Owner notifies reward
        vm.prank(owner);
        staking.notifyRewardAmount(70 ether);

        // Move time forward
        vm.warp(block.timestamp + 1 days);

        // Check earned rewards
        uint256 earnedBefore = staking.earned(bob);
        assertTrue(earnedBefore > 0, "Should have earned rewards");

        // Claim rewards
        vm.prank(bob);
        staking.getReward();

        // Check earned is reset
        assertEq(staking.earned(bob), 0, "Should reset to 0 after claiming");
    }

    function test_getReward() public {
        // Setup staking and rewards
        vm.prank(owner);
        staking.setRewardsDuration(1 weeks);

        deal(address(stakingToken), bob, 100 ether);
        deal(address(rewardToken), address(staking), 70 ether);

        // Bob stakes tokens
        vm.startPrank(bob);
        stakingToken.approve(address(staking), 50 ether);
        staking.stake(50 ether);
        vm.stopPrank();

        // Owner notifies reward
        vm.prank(owner);
        staking.notifyRewardAmount(70 ether);

        // Move time forward
        vm.warp(block.timestamp + 1 days);

        // Get initial balances
        uint256 bobRewardsBefore = rewardToken.balanceOf(bob);
        uint256 earnedBefore = staking.earned(bob);
        assertTrue(earnedBefore > 0, "Should have earned rewards");

        // Claim rewards
        vm.prank(bob);
        staking.getReward();

        // Verify rewards were transferred
        assertEq(rewardToken.balanceOf(bob) - bobRewardsBefore, earnedBefore, "Reward transfer amount incorrect");
        assertEq(staking.rewards(bob), 0, "Rewards not reset to 0");

        // Try claiming again immediately
        vm.prank(bob);
        staking.getReward(); // Should not revert, but also not transfer any tokens
        assertEq(rewardToken.balanceOf(bob) - bobRewardsBefore, earnedBefore, "Second claim should not transfer additional tokens");
    }

    function test_notifyRewardAmount_midPeriod() public {
        // Setup initial staking and rewards
        vm.startPrank(owner);
        staking.setRewardsDuration(1 weeks);
        deal(address(rewardToken), address(staking), 170 ether);

        // First reward notification
        staking.notifyRewardAmount(70 ether);
        uint256 initialRewardRate = staking.rewardRate();

        // Move time forward to middle of reward period
        vm.warp(block.timestamp + 3.5 days);

        // Calculate remaining rewards
        uint256 remainingTime = staking.finishAt() - block.timestamp;
        uint256 remainingRewards = remainingTime * initialRewardRate;

        // Add more rewards mid-period
        uint256 additionalReward = 100 ether;
        staking.notifyRewardAmount(additionalReward);

        // Verify new reward rate
        uint256 expectedRate = (additionalReward + remainingRewards) / staking.duration();
        assertEq(staking.rewardRate(), expectedRate, "New reward rate calculation incorrect");

        // Verify finish time is extended
        assertEq(staking.finishAt(), block.timestamp + 1 weeks, "Finish time not extended correctly");
        vm.stopPrank();
    }
}