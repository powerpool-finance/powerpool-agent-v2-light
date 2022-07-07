// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";

contract StakingTest is TestHelper {
  uint256 internal kid;

  function setUp() public override {
    cvp = new MockCVP();
    agent = new PPAgentV2(owner, address(cvp), MIN_DEPOSIT_3000_CVP, 3 days);
    cvp.transfer(keeperAdmin, 16_000 ether);
    vm.startPrank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP * 2);
    agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);
    kid = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);
    vm.stopPrank();
  }

  function testErrSlashNotOwner() public {
    vm.expectRevert(PPAgentV2.OnlyOwner.selector);
    agent.slash(kid, bob, 1);
  }

  function testErrSlashZeroAmount() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingAmount.selector)
    );
    vm.prank(owner);
    agent.slash(kid, bob, 0);
  }

  function testFailNonExistentKeeper() public {
    vm.prank(owner);
    agent.slash(999, bob, 1); // fails
  }

  function testSlashPartOfTheDeposit() public {
    vm.prank(keeperAdmin);

    assertEq(agent.balanceOf(keeperAdmin), 6_000 ether);
    assertEq(_stakeOf(kid), 3_000 ether);
    assertEq(_slashedStakeOf(kid), 0);
    assertEq(cvp.balanceOf(keeperAdmin), 10_000 ether);
    assertEq(cvp.balanceOf(address(agent)), 6_000 ether);

    vm.prank(owner);
    agent.slash(kid, bob, 500 ether);

    assertEq(agent.balanceOf(keeperAdmin), 6_000 ether);
    assertEq(_stakeOf(kid), 2_500 ether);
    assertEq(_slashedStakeOf(kid), 500 ether);
    assertEq(cvp.balanceOf(keeperAdmin), 10_000 ether);
    assertEq(cvp.balanceOf(address(agent)), 5_500 ether);
    assertEq(cvp.balanceOf(bob), 500 ether);
  }

  function testErrWontRedeemLtPartiallySlashed() public {
    vm.prank(owner);
    agent.slash(kid, bob, 500 ether);

    // Wont burn
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.InsufficientAmountToCoverSlashedStake.selector, 499 ether, 500 ether)
    );
    vm.prank(keeperAdmin);
    agent.initiateRedeem(kid, 499 ether);
  }

  function testRedeemExactPartiallySlashed() public {
    vm.prank(owner);
    agent.slash(kid, bob, 500 ether);

    vm.prank(keeperAdmin);
    agent.initiateRedeem(kid, 500 ether);

    assertEq(agent.balanceOf(keeperAdmin), 5_500 ether);
    assertEq(_stakeOf(kid), 2_500 ether);
    assertEq(_slashedStakeOf(kid), 0);
    assertEq(cvp.balanceOf(keeperAdmin), 10_000 ether);
    assertEq(cvp.balanceOf(address(agent)), 5_500 ether);

    vm.warp(block.timestamp + 3 days + 1);
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.NoPendingWithdrawal.selector)
    );
    vm.prank(keeperAdmin);
    agent.finalizeRedeem(kid, keeperAdmin);
  }

  function testRedeemGtPartiallySlashed() public {
    vm.prank(owner);
    agent.slash(kid, bob, 500 ether);

    vm.prank(keeperAdmin);
    agent.initiateRedeem(kid, 600 ether);

    assertEq(agent.balanceOf(keeperAdmin), 5_400 ether);
    assertEq(_stakeOf(kid), 2_400 ether);
    assertEq(_slashedStakeOf(kid), 0);
    assertEq(cvp.balanceOf(keeperAdmin), 10_000 ether);
    assertEq(cvp.balanceOf(address(agent)), 5_500 ether);
    assertEq(_pendingWithdrawalAmountOf(kid), 100 ether);

    vm.warp(block.timestamp + 3 days + 1);
    vm.prank(keeperAdmin);
    agent.finalizeRedeem(kid, keeperAdmin);

    assertEq(agent.balanceOf(keeperAdmin), 5_400 ether);
    assertEq(_stakeOf(kid), 2_400 ether);
    assertEq(_slashedStakeOf(kid), 0);
    assertEq(_pendingWithdrawalAmountOf(kid), 0);
    assertEq(cvp.balanceOf(keeperAdmin), 10_000 ether + 100 ether);
    assertEq(cvp.balanceOf(address(agent)), 5_400 ether);
  }

  function testErrWontRedeemLtFullySlashed() public {
    vm.prank(owner);
    agent.slash(kid, bob, 3_000 ether);

    // Wont burn
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.InsufficientAmountToCoverSlashedStake.selector, 2_999 ether, 3_000 ether)
    );
    vm.prank(keeperAdmin);
    agent.initiateRedeem(kid, 2_999 ether);
  }

  function testRedeemFullySlashed() public {
    vm.prank(owner);
    agent.slash(kid, bob, 3_000 ether);

    vm.prank(keeperAdmin);
    agent.initiateRedeem(kid, 3_000 ether);

    assertEq(agent.balanceOf(keeperAdmin), 3_000 ether);
    assertEq(_stakeOf(kid), 0);
    assertEq(_slashedStakeOf(kid), 0 ether);
    assertEq(cvp.balanceOf(keeperAdmin), 10_000 ether);
    assertEq(cvp.balanceOf(address(agent)), 3_000 ether);

    vm.warp(block.timestamp + 3 days + 1);
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.NoPendingWithdrawal.selector)
    );
    vm.prank(keeperAdmin);
    agent.finalizeRedeem(kid, keeperAdmin);
  }
}
