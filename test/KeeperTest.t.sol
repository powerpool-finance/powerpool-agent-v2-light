// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";

contract KeeperTest is TestHelper {
  uint256 internal kid;

  event RegisterAsKeeper(uint256 indexed keeperId, address indexed keeperAdmin, address indexed keeperWorker);
  event Stake(uint256 indexed keeperId, uint256 amount, address staker);
  event WithdrawCompensation(uint256 indexed keeperId, address indexed to, uint256 amount);
  event SetWorkerAddress(uint256 indexed keeperId, address indexed prev, address indexed worker);

  function setUp() public override {
    cvp = new MockCVP();
    agent = new PPAgentV2(bob, address(cvp), MIN_DEPOSIT_3000_CVP, 3 days);
    cvp.transfer(keeperAdmin, 10_000 ether);
    vm.startPrank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP * 2);
    kid = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP);
    vm.stopPrank();

    vm.deal(address(agent), 20 ether);
    bytes32 rewardSlotKey = keccak256(abi.encode(kid, 16 /* compensations slot */));
    vm.store(address(agent), rewardSlotKey, bytes32(uint256(20 ether)));
  }

  function testKeeperRegistration() public {
    assertEq(address(agent).balance, 20 ether);
    assertEq(_compensationOf(kid), 20 ether);

    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP * 2);

    vm.prank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP * 2);

    assertEq(kid, 1);
    (,,,,uint256 lastKeeperId) = agent.getConfig();
    assertEq(lastKeeperId, 1);

    address keeperWorker2 = address(1);
    vm.expectEmit(true, true, false, true, address(agent));
    emit RegisterAsKeeper(2, keeperAdmin, keeperWorker2);
    vm.expectEmit(true, true, false, true, address(agent));
    emit Stake(2, MIN_DEPOSIT_3000_CVP, keeperAdmin);

    vm.prank(keeperAdmin);
    kid = agent.registerAsKeeper(keeperWorker2, MIN_DEPOSIT_3000_CVP);

    assertEq(kid, 2);
    (,,,,lastKeeperId) = agent.getConfig();
    assertEq(lastKeeperId, 2);

    assertEq(_stakeOf(2), MIN_DEPOSIT_3000_CVP);
    assertEq(_workerOf(2), keeperWorker2);
    assertEq(agent.workerKeeperIds(keeperWorker2), 2);

    address keeperWorker3 = address(3);
    vm.prank(keeperAdmin);
    kid = agent.registerAsKeeper(keeperWorker3, MIN_DEPOSIT_3000_CVP);

    assertEq(agent.workerKeeperIds(keeperWorker3), 3);
    assertEq(kid, 3);

    (,,,,lastKeeperId) = agent.getConfig();
    assertEq(lastKeeperId, 3);
  }

  function testErrKeeperRegistrationWorkerAlreadyAssigned() public {
    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP);

    vm.prank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP);

    vm.expectRevert(PPAgentV2.WorkerAlreadyAssigned.selector);
    kid = agent.registerAsKeeper(keeperWorker, MIN_DEPOSIT_3000_CVP - 1);
  }

  function testErrKeeperRegistrationInsufficientDeposit() public {
    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP);

    vm.prank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP);

    vm.expectRevert(PPAgentV2.InsufficientAmount.selector);
    address keeperWorker2 = address(1);
    kid = agent.registerAsKeeper(keeperWorker2, MIN_DEPOSIT_3000_CVP - 1);
  }

  function testKeeperFullCompensationWithdrawalToAnotherAddress() public {
    assertEq(alice.balance, 0);
    assertEq(_compensationOf(kid), 20 ether);

    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawCompensation(kid, alice, 20 ether);

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 20 ether);

    assertEq(_compensationOf(kid), 0);
    assertEq(alice.balance, 20 ether);
  }

  function testKeeperWorkerFullCompensationWithdrawalToAnotherAddress() public {
    assertEq(alice.balance, 0);
    assertEq(_compensationOf(kid), 20 ether);

    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawCompensation(kid, alice, 20 ether);

    vm.prank(keeperWorker);
    agent.withdrawCompensation(kid, alice, 20 ether);

    assertEq(_compensationOf(kid), 0);
    assertEq(alice.balance, 20 ether);
  }

  function testKeeperCurrentCompensationWithdrawalToAnotherAddress() public {
    assertEq(alice.balance, 0);
    assertEq(_compensationOf(kid), 20 ether);

    vm.expectEmit(true, true, false, true, address(agent));
    emit WithdrawCompensation(kid, alice, 20 ether);

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, type(uint256).max);

    assertEq(_compensationOf(kid), 0);
    assertEq(alice.balance, 20 ether);
  }

  function testKeeperPartialCompensationWithdrawalToAnotherAddress() public {
    assertEq(alice.balance, 0);
    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 15 ether);
    assertEq(alice.balance, 15 ether);
    assertEq(_compensationOf(kid), 5 ether);

    vm.prank(keeperAdmin);
    agent.withdrawCompensation(kid, alice, 5 ether);
    assertEq(alice.balance, 20 ether);
    assertEq(_compensationOf(kid), 0);
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

  function testSetWorker() public {
    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP);

    address newWorker = address(1);

    assertEq(agent.workerKeeperIds(keeperWorker), kid);
    assertEq(agent.workerKeeperIds(newWorker), 0);
    assertEq(_workerOf(kid), keeperWorker);
    assertEq(_stakeOf(kid), 3000 ether);

    (address worker, uint256 stake) = agent.getKeeperWorkerAndStake(kid);
    assertEq(worker, keeperWorker);
    assertEq(stake, 3000 ether);

    vm.expectEmit(true, true, false, true, address(agent));
    emit SetWorkerAddress(kid, keeperWorker, newWorker);
    vm.prank(keeperAdmin);
    agent.setWorkerAddress(kid, newWorker);

    assertEq(agent.workerKeeperIds(keeperWorker), 0);
    assertEq(agent.workerKeeperIds(newWorker), kid);
    assertEq(_workerOf(kid), newWorker);
  }

  function testUnsetWorker() public {
    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP);

    vm.prank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP);

    address newWorker = address(0);

    assertEq(agent.workerKeeperIds(keeperWorker), kid);
    assertEq(agent.workerKeeperIds(newWorker), 0);
    assertEq(_workerOf(kid), keeperWorker);

    vm.prank(keeperAdmin);
    agent.setWorkerAddress(kid, newWorker);

    assertEq(agent.workerKeeperIds(keeperWorker), 0);
    assertEq(agent.workerKeeperIds(newWorker), kid);
    assertEq(_workerOf(kid), newWorker);
  }

  function testErrSetWorkerAlreadyTaken() public {
    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP);

    vm.startPrank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP);

    address keeperWorker2 = address(2);
    uint256 kid2 = agent.registerAsKeeper(keeperWorker2, MIN_DEPOSIT_3000_CVP);

    vm.expectRevert(PPAgentV2.WorkerAlreadyAssigned.selector);
    agent.setWorkerAddress(kid2, keeperWorker);
    agent.setWorkerAddress(kid, address(0));
    agent.setWorkerAddress(kid2, keeperWorker);

    vm.stopPrank();
  }

  function testErrSetWorkerNotAdmin() public {
    cvp.transfer(keeperAdmin, MIN_DEPOSIT_3000_CVP);

    vm.prank(keeperAdmin);
    cvp.approve(address(agent), MIN_DEPOSIT_3000_CVP);

    vm.expectRevert(PPAgentV2.OnlyKeeperAdmin.selector);
    agent.setWorkerAddress(kid, address(1));
  }
}
