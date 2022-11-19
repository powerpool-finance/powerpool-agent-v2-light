// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";

contract AgentOwnerTest is TestHelper {
  uint256 internal kid;

  event SetAgentParams(uint256 minKeeperCvp_, uint256 timeoutSeconds_, uint256 feePct_);
  event WithdrawFees(address indexed to, uint256 amount);

  function setUp() public override {
    cvp = new MockCVP();
    agent = new PPAgentV2(owner, address(cvp), MIN_DEPOSIT_3000_CVP, 3 days);
  }

  function testOwnerAssignedCorrectly() public {
    assertEq(agent.owner(), owner);
  }

  // setAgentParams()

  function testSetAgentParams() public {
    vm.expectEmit(true, true, false, true, address(agent));
    emit SetAgentParams(type(uint256).max, 30 days, 1.5e4);

    vm.prank(owner);
    agent.setAgentParams(type(uint256).max, 30 days, 1.5e4);
    (
      uint256 minKeeperCvp,
      uint256 pendingWithdrawalTimeoutSeconds,
      ,
      uint256 feePpm,
    ) = agent.getConfig();

    assertEq(minKeeperCvp, type(uint256).max);
    assertEq(pendingWithdrawalTimeoutSeconds, 30 days);
    assertEq(feePpm, 1.5e4);
  }

  function testErrSetAgentParamsNotOwner() public {
    vm.expectRevert(PPAgentV2.OnlyOwner.selector);
    agent.setAgentParams(type(uint256).max, 30 days, 1.5e4);
  }

  function testSetPendingWithdrawalTimeoutZero() public {
    vm.prank(owner);
    agent.setAgentParams(2, 0, 2);
    (,uint256 pendingWithdrawalTimeoutSeconds,,,) = agent.getConfig();
    assertEq(pendingWithdrawalTimeoutSeconds, 0);
  }

  function testErrSetPendingWithdrawalTimeoutTooBig() public {
    vm.expectRevert(PPAgentV2.TimeoutTooBig.selector);
    vm.prank(owner);
    agent.setAgentParams(2, 30 days + 1, 2);
  }

  function testErrSetFeeTooBig() public {
    vm.expectRevert(PPAgentV2.FeeTooBig.selector);
    vm.prank(owner);
    agent.setAgentParams(2, 30 days, 5e4+1);
  }

  // withdrawFees()

  function testWithdrawFees() public {
    vm.deal(address(agent), 30 ether);
    vm.store(address(agent), bytes32(uint256(3))/* feeTotal slot */, bytes32(uint256(20 ether)));

    assertEq(address(agent).balance, 30 ether);
    (,,uint256 feeTotal,,) = agent.getConfig();
    assertEq(feeTotal, 20 ether);
    assertEq(bob.balance, 0);

    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawFees(bob, 20 ether);
    vm.prank(owner);
    agent.withdrawFees(bob);

    assertEq(address(agent).balance, 10 ether);
    (,,feeTotal,,) = agent.getConfig();
    assertEq(feeTotal, 0);
    assertEq(bob.balance, 20 ether);
  }

  function testErrWithdrawFeesNotOwner() public {
    vm.expectRevert(PPAgentV2.OnlyOwner.selector);
    agent.withdrawFees(bob);
  }
}
