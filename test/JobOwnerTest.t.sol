// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";

contract JobOwnerTest is TestHelper {
  event DepositJobOwnerCredits(address indexed jobOwner, address indexed depositor, uint256 amount, uint256 fee);
  event WithdrawJobOwnerCredits(address indexed jobOwner, address indexed to, uint256 amount);

  MockCVP internal cvp;
  PPAgentV2 internal agent;

  function setUp() public override {
    vm.deal(alice, 100 ether);
    vm.deal(bob, 100 ether);
    cvp = new MockCVP();
    agent = new PPAgentV2(owner, address(cvp), 3_000 ether, 3 days);
    vm.deal(address(agent), 1000 ether);
    cvp.transfer(alice, 10_000 ether);
  }

  function testAddJobOwnerCreditsNoFee(uint128 amount1, uint128 amount2) public {
    vm.assume(amount1 > 0 && amount2 > 0);
    vm.deal(alice, amount1);
    vm.deal(bob, amount2);

    // 1st deposit
    uint256 aliceBalanceBefore = alice.balance;
    uint256 bobBalanceBefore = bob.balance;
    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobOwnerCredits(bob, alice, amount1, 0);

    vm.prank(alice);
    agent.depositJobOwnerCredits{ value: amount1}(bob);

    assertEq(amount1, agent.jobOwnerCredits(bob));
    assertEq(aliceBalanceBefore - amount1, alice.balance);

    // 2nd deposit
    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobOwnerCredits(bob, bob, amount2, 0);
    vm.prank(bob);
    agent.depositJobOwnerCredits{ value: amount2}(bob);

    assertEq(uint256(amount1) + uint256(amount2), agent.jobOwnerCredits(bob));
    assertEq(aliceBalanceBefore - amount1, alice.balance);
    assertEq(bobBalanceBefore - amount2, bob.balance);
  }

  function testAddJobOwnerCreditsWithFee(uint128 deposit1, uint128 deposit2) public {
    vm.assume(deposit1 > 0 && deposit2 > 0);
    vm.deal(alice, deposit1);
    vm.deal(bob, deposit2);

    vm.prank(owner);
    agent.setAgentParams(3_000 ether, 30 days, 4e4);

    // 1st deposit
    uint256 fee1 = uint256(deposit1) * 4e4 / 1e6;
    uint256 amount1 = deposit1 - fee1;
    uint256 aliceBalanceBefore = alice.balance;
    uint256 bobBalanceBefore = bob.balance;
    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobOwnerCredits(bob, alice, amount1, fee1);

    vm.prank(alice);
    agent.depositJobOwnerCredits{ value: deposit1}(bob);

    assertEq(agent.jobOwnerCredits(bob), amount1);
    assertEq(alice.balance, aliceBalanceBefore - deposit1);

    assertEq(agent.jobOwnerCredits(bob), amount1);
    assertEq(agent.feeTotal(), fee1);

    // 2nd deposit
    uint256 fee2 = uint256(deposit2) * 4e4 / 1e6;
    uint256 amount2 = deposit2 - fee2;
    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobOwnerCredits(bob, bob, amount2, fee2);
    vm.prank(bob);
    agent.depositJobOwnerCredits{ value: deposit2 }(bob);

    assertEq(agent.jobOwnerCredits(bob), uint256(amount1) + uint256(amount2));
    assertEq(alice.balance, aliceBalanceBefore - deposit1);
    assertEq(bob.balance, bobBalanceBefore - deposit2);
    assertEq(agent.feeTotal(), fee1 + fee2);
  }

  function testErrAddJobOwnerCreditsZeroDeposit() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingDeposit.selector)
    );

    vm.prank(alice);
    agent.depositJobOwnerCredits{ value: 0 ether}(bob);
  }

  function testWithdrawJobOwnerCredits() public {
    vm.prank(alice);
    agent.depositJobOwnerCredits{ value: 10 ether}(alice);
    assertEq(agent.jobOwnerCredits(alice), 10 ether);

    uint256 aliceBalanceBefore = alice.balance;
    uint256 bobBalanceBefore = bob.balance;

    // 1st withdrawal
    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawJobOwnerCredits(alice, bob, 3 ether);

    vm.prank(alice);
    agent.withdrawJobOwnerCredits(bob, 3 ether);

    assertEq(agent.jobOwnerCredits(alice), 7 ether);
    assertEq(bob.balance, bobBalanceBefore + 3 ether);

    // 2nd withdrawal
    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawJobOwnerCredits(alice, alice, 7 ether);
    vm.prank(alice);
    agent.withdrawJobOwnerCredits(alice, 7 ether);

    assertEq(agent.jobOwnerCredits(alice), 0 ether);
    assertEq(alice.balance, aliceBalanceBefore + 7 ether);
    assertEq(bob.balance, bobBalanceBefore + 3 ether);
  }

  function testWithdrawCurrentJobOwnerCredits() public {
    vm.prank(alice);
    agent.depositJobOwnerCredits{ value: 10 ether}(alice);
    assertEq(agent.jobOwnerCredits(alice), 10 ether);
    uint256 bobBalanceBefore = bob.balance;

    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawJobOwnerCredits(alice, bob, 10 ether);

    vm.prank(alice);
    agent.withdrawJobOwnerCredits(bob, type(uint256).max);

    assertEq(agent.jobOwnerCredits(alice), 0 ether);
    assertEq(bob.balance, bobBalanceBefore + 10 ether);
  }

  function testErrRemoveJobOwnerCreditsMissingAmount() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingAmount.selector)
    );

    vm.prank(alice);
    agent.withdrawJobOwnerCredits(alice, 0);
  }

  function testErrRemoveJobOwnerCreditsCreditsWithdrawalUnderflow() public {
    vm.prank(alice);
    agent.depositJobOwnerCredits{ value: 10 ether}(alice);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.CreditsWithdrawalUnderflow.selector)
    );

    vm.prank(alice);
    agent.withdrawJobOwnerCredits(alice, 11 ether);
  }

  function testErrRemoveJobOwnerCreditsCreditsRevert() public {
    vm.prank(alice);
    agent.depositJobOwnerCredits{ value: 10 ether}(alice);

    vm.expectRevert(bytes("SOME_REASON"));

    vm.prank(alice);
    agent.withdrawJobOwnerCredits(payable(this), 10 ether);
  }

  receive() external payable {
    revert("SOME_REASON");
  }
}
