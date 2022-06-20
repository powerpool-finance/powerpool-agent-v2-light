// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentLite.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";

contract StakingTest is TestHelper {
  MockCVP internal cvp;
  PPAgentLite internal agent;
  uint256 internal kid0;
  uint256 internal kid1;

  function setUp() public override {
    cvp = new MockCVP();
    agent = new PPAgentLite(owner, address(cvp), MIN_DEPOSIT_3000_CVP, 3 days);
    cvp.transfer(keeperAdmin, CVP_TOTAL_SUPPLY + MIN_DEPOSIT_3000_CVP * 2);

    vm.startPrank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP * 2);
    kid0 = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);
    kid1 = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);
    vm.stopPrank();
  }

  function testDepositToTheOwnedKid(uint96 amount1, uint96 amount2) public {
    vm.assume(uint256(amount1) + uint256(amount2) <= CVP_TOTAL_SUPPLY);
    vm.assume(amount1 > 0 && amount2 > 0);

    uint256 keeperAdminBalanceBefore = cvp.balanceOf(keeperAdmin);
    assertEq(agent.balanceOf(keeperAdmin), 6_000 ether);
    assertEq(agent.stakeOf(kid1), 3_000 ether);
    assertEq(cvp.balanceOf(keeperAdmin), keeperAdminBalanceBefore);
    assertEq(cvp.balanceOf(address(agent)), 6_000 ether);

    vm.startPrank(keeperAdmin);
    cvp.approve(address(agent), amount1);
    agent.stake(kid1, keeperAdmin, amount1);
    vm.stopPrank();

    assertEq(agent.balanceOf(keeperAdmin), amount1 + 6_000 ether);
    assertEq(agent.stakeOf(kid1), amount1 + 3_000 ether);
    assertEq(cvp.balanceOf(keeperAdmin), keeperAdminBalanceBefore - amount1);
    assertEq(cvp.balanceOf(address(agent)), amount1 + 6_000 ether);
  }

  function testDepositForTheNonOwnedKid() public {
    assertEq(agent.balanceOf(keeperAdmin), 6_000 ether);
    assertEq(agent.stakeOf(kid1), 3_000 ether);
    assertEq(agent.balanceOf(charlie), 0 ether);

    vm.prank(keeperAdmin);
    cvp.transfer(bob, 3_500 ether);

    vm.startPrank(bob);
    cvp.approve(address(agent), 3_500 ether);
    agent.stake(kid1, charlie, 3_500 ether);
    vm.stopPrank();

    assertEq(agent.balanceOf(keeperAdmin), 6_000 ether);
    assertEq(agent.stakeOf(kid1), 6_500 ether);
    assertEq(agent.balanceOf(charlie), 3_500 ether);
    assertEq(agent.stakeOf(kid0), 3_000 ether);
  }

  function testRedeemOnceToTheAdminAddress(uint256 amount) public {
    vm.assume(amount < 100_000_000 ether);
    vm.assume(amount > 500 ether);

    uint256 keeperAdminBalanceBefore = cvp.balanceOf(keeperAdmin);
    cvp.approve(address(agent), amount);
    agent.stake(kid1, keeperAdmin, amount);

    assertEq(agent.stakeOf(kid1), amount + 3_000 ether);
    assertEq(agent.balanceOf(keeperAdmin), amount + 6_000 ether);
    assertEq(cvp.balanceOf(keeperAdmin), keeperAdminBalanceBefore);
    assertEq(agent.pendingWithdrawalAmount(kid1), 0);

    vm.startPrank(keeperAdmin);
    agent.initiateRedeem(kid1, 500 ether);
    vm.expectRevert(abi.encodeWithSelector(PPAgentLite.WithdrawalTimoutNotReached.selector));
    agent.finalizeRedeem(kid1, keeperAdmin);
    vm.warp(block.timestamp + 2 days);
    vm.expectRevert(abi.encodeWithSelector(PPAgentLite.WithdrawalTimoutNotReached.selector));
    agent.finalizeRedeem(kid1, keeperAdmin);

    assertEq(agent.balanceOf(keeperAdmin), amount + 6_000 ether - 500 ether);
    assertEq(agent.stakeOf(kid1), amount + 3_000 ether - 500 ether);
    assertEq(cvp.balanceOf(keeperAdmin), keeperAdminBalanceBefore);
    assertEq(agent.pendingWithdrawalAmount(kid1), 500 ether);
    assertEq(agent.pendingWithdrawalEndsAt(kid1), block.timestamp + 1 days);

    vm.warp(block.timestamp + 1 days + 1);
    agent.finalizeRedeem(kid1, keeperAdmin);

    assertEq(agent.balanceOf(keeperAdmin), amount + 6_000 ether - 500 ether);
    assertEq(agent.stakeOf(kid1), amount + 3_000 ether - 500 ether);
    assertEq(cvp.balanceOf(keeperAdmin), keeperAdminBalanceBefore + 500 ether);

    assertEq(agent.pendingWithdrawalAmount(kid1), 0);
    assertEq(agent.pendingWithdrawalEndsAt(kid1), block.timestamp - 1);

    agent.initiateRedeem(kid1, amount + 3_000 ether - 500 ether);
    vm.warp(block.timestamp + 3 days + 1);
    agent.finalizeRedeem(kid1, keeperAdmin);
    vm.stopPrank();

    assertEq(agent.balanceOf(keeperAdmin), 3_000 ether);
    assertEq(agent.stakeOf(kid1), 0);
    assertEq(cvp.balanceOf(keeperAdmin), keeperAdminBalanceBefore + amount + 3_000 ether);
    assertEq(agent.pendingWithdrawalAmount(kid1), 0);
    assertEq(agent.pendingWithdrawalEndsAt(kid1), block.timestamp - 1);
  }

  function testRedeemAccumulatedToTheAdminAddress() public {
    assertEq(agent.stakeOf(kid1), 3_000 ether);
    assertEq(agent.balanceOf(keeperAdmin), 6_000 ether);
    assertEq(cvp.balanceOf(keeperAdmin), 100_000_000 ether);
    assertEq(agent.pendingWithdrawalAmount(kid1), 0);

    // Redeem #1
    vm.startPrank(keeperAdmin);
    agent.initiateRedeem(kid1, 500 ether);
    vm.expectRevert(abi.encodeWithSelector(PPAgentLite.WithdrawalTimoutNotReached.selector));
    agent.finalizeRedeem(kid1, keeperAdmin);

    assertEq(agent.balanceOf(keeperAdmin), 5_500 ether);
    assertEq(agent.stakeOf(kid1), 2_500 ether);
    assertEq(cvp.balanceOf(keeperAdmin), 100_000_000 ether);
    assertEq(agent.pendingWithdrawalAmount(kid1), 500 ether);
    assertEq(agent.pendingWithdrawalEndsAt(kid1), block.timestamp + 3 days);

    // Redeem #2
    vm.warp(block.timestamp + 1 days);
    agent.initiateRedeem(kid1, 500 ether);

    assertEq(agent.balanceOf(keeperAdmin), 5_000 ether);
    assertEq(agent.stakeOf(kid1), 2_000 ether);
    assertEq(cvp.balanceOf(keeperAdmin), 100_000_000 ether);
    assertEq(agent.pendingWithdrawalAmount(kid1), 1_000 ether);
    assertEq(agent.pendingWithdrawalEndsAt(kid1), block.timestamp + 3 days);

    // Redeem #3
    vm.warp(block.timestamp + 4 days);
    agent.initiateRedeem(kid1, 2_000 ether);
    assertEq(agent.balanceOf(keeperAdmin), 3_000 ether);
    assertEq(agent.stakeOf(kid1), 0);
    assertEq(cvp.balanceOf(keeperAdmin), 100_000_000 ether);
    assertEq(agent.pendingWithdrawalAmount(kid1), 3_000 ether);
    assertEq(agent.pendingWithdrawalEndsAt(kid1), block.timestamp + 3 days);

    // Finalize
    vm.warp(block.timestamp + 3 days + 1);
    agent.finalizeRedeem(kid1, keeperAdmin);
    assertEq(agent.balanceOf(keeperAdmin), 3_000 ether);
    assertEq(agent.stakeOf(kid1), 0);
    assertEq(cvp.balanceOf(keeperAdmin), 100_003_000 ether);
    assertEq(agent.pendingWithdrawalAmount(kid1), 0);
    assertEq(agent.pendingWithdrawalEndsAt(kid1), block.timestamp - 1);

    vm.expectRevert(PPAgentLite.NoPendingWithdrawal.selector);
    agent.finalizeRedeem(kid1, keeperAdmin);
    vm.stopPrank();
  }

  function testRedeemToNonOwnerAddress() public {
    vm.startPrank(keeperAdmin);
    agent.initiateRedeem(kid1, 500 ether);
    vm.warp(block.timestamp + 3 days + 1);
    agent.finalizeRedeem(kid1, bob);

    assertEq(agent.balanceOf(keeperAdmin), 5_500 ether);
    assertEq(agent.stakeOf(kid1), 2_500 ether);
    assertEq(agent.balanceOf(bob), 0 ether);
    assertEq(cvp.balanceOf(bob), 500 ether);

    agent.initiateRedeem(kid1, 2_500 ether);
    vm.warp(block.timestamp + 3 days + 1);
    agent.finalizeRedeem(kid1, bob);
    vm.stopPrank();

    assertEq(agent.balanceOf(keeperAdmin), 3_000 ether);
    assertEq(agent.stakeOf(kid1), 0);
    assertEq(cvp.balanceOf(bob), 3_000 ether);
  }

  function testRedeemWithNotEnoughStake() public {
    cvp.approve(address(agent), 3_500 ether);
    agent.stake(kid0, bob, 3_500 ether);

    vm.prank(bob);
    agent.transfer(keeperAdmin, 3_500 ether);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentLite.AmountGtStake.selector, 3_001 ether, 3_000 ether, 0)
    );
    vm.prank(keeperAdmin);
    agent.initiateRedeem(kid1, 3_001 ether);
  }

  function testRedeemWithNotEnoughErc20Tokens() public {
    vm.prank(keeperAdmin);
    agent.transfer(bob, 3_001 ether);

    vm.prank(keeperAdmin);
    vm.expectRevert(bytes("ERC20: burn amount exceeds balance"));
    agent.initiateRedeem(kid1, 3_000 ether);
  }

  function testErrStakeZero() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentLite.MissingAmount.selector)
    );
    agent.stake(kid1, keeperAdmin, 0);
  }

  function testErrRedeemZero() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentLite.MissingAmount.selector)
    );
    vm.prank(keeperAdmin);
    agent.initiateRedeem(kid1, 0);
  }
}
