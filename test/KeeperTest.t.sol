// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";

contract KeeperTest is TestHelper {
  MockCVP internal cvp;
  PPAgentV2 internal agent;
  uint256 internal kid;

  event RegisterAsKeeper(uint256 indexed keeperId, address indexed keeperAdmin, address indexed keeperWorker);
  event Stake(uint256 indexed keeperId, uint256 amount, address staker, address receiver);
  event WithdrawCompensation(uint256 indexed keeperId, address indexed to, uint256 amount);

  function setUp() public override {
    cvp = new MockCVP();
    agent = new PPAgentV2(bob, address(cvp), MIN_DEPOSIT_3000_CVP, 3 days);
    cvp.transfer(keeperAdmin, 10_000 ether);
    vm.startPrank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP * 2);
    kid = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);
    vm.stopPrank();

    vm.deal(address(agent), 20 ether);
    bytes32 rewardSlotKey = keccak256(abi.encode(kid, 22 /* compensations slot */));
    vm.store(address(agent), rewardSlotKey, bytes32(uint256(20 ether)));
  }

  function testKeeperRegistration() public {
    assertEq(address(agent).balance, 20 ether);
    assertEq(agent.compensations(kid), 20 ether);

    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP * 2);

    vm.prank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP * 2);

    assertEq(kid, 0);

    vm.expectEmit(true, true, false, true, address(agent));
    emit RegisterAsKeeper(1, keeperAdmin, keeperWorker);
    vm.expectEmit(true, true, false, true, address(agent));
    emit Stake(1, MIN_DEPOSIT_3000_CVP, keeperAdmin, keeperAdmin);

    vm.prank(keeperAdmin);
    kid = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);

    assertEq(kid, 1);

    assertEq(agent.stakeOf(1), MIN_DEPOSIT_3000_CVP);
    assertEq(agent.keeperInfo(1).cvpStake, MIN_DEPOSIT_3000_CVP);
    assertEq(agent.keeperInfo(1).worker, keeperWorker);

    vm.prank(keeperAdmin);
    kid = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);

    assertEq(kid, 2);
  }

  function testErrKeeperRegistrationInsufficientDeposit() public {
    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP);

    vm.prank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP);

    vm.expectRevert(PPAgentV2.InsufficientAmount.selector);
    kid = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP - 1);
  }

  function testKeeperFullCompensationWithdrawalToAnotherAddress() public {
    assertEq(alice.balance, 0);
    assertEq(agent.compensations(kid), 20 ether);

    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawCompensation(kid, alice, 20 ether);

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 20 ether);

    assertEq(agent.compensations(kid), 0);
    assertEq(alice.balance, 20 ether);
  }

  function testKeeperCurrentCompensationWithdrawalToAnotherAddress() public {
    assertEq(alice.balance, 0);
    assertEq(agent.compensations(kid), 20 ether);

    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawCompensation(kid, alice, 20 ether);

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, type(uint256).max);

    assertEq(agent.compensations(kid), 0);
    assertEq(alice.balance, 20 ether);
  }

  function testKeeperPartialCompensationWithdrawalToAnotherAddress() public {
    assertEq(alice.balance, 0);
    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 15 ether);
    assertEq(alice.balance, 15 ether);
    assertEq(agent.compensations(kid), 5 ether);

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 5 ether);
    assertEq(alice.balance, 20 ether);
    assertEq(agent.compensations(kid), 0);
  }

  function testErrWithdrawExtraCompensation() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.WithdrawAmountExceedsAvailable.selector, 22 ether, 20 ether)
    );

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 22 ether);
  }

  function testErrWithdrawAnotherExtraCompensation() public {
    vm.expectRevert(abi.encodeWithSelector(
      PPAgentV2.WithdrawAmountExceedsAvailable.selector,
      21 ether,
      20 ether
    ));

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 21 ether);
  }

  function testErrWithdrawZeroCompensation() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingAmount.selector)
    );

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 0);
  }
}
