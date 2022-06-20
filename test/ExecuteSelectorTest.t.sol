// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentLite.sol";
import "./jobs/OnlySelectorTestJob.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";
import "forge-std/Vm.sol";

contract ExecuteSelectorTest is TestHelper {
  event Execute(bytes32 indexed jobKey, address indexed job, bool indexed success, uint256 gasUsed, uint256 baseFee, uint256 gasPrice, uint256 compensation);

  MockCVP internal cvp;
  PPAgentLite internal agent;
  OnlySelectorTestJob internal counter;

  bytes32 internal jobKey;
  uint256 internal jobId;
  uint256 internal defaultFlags;
  uint256 internal accrueFlags;
  uint256 internal kid;

  function setUp() public override {
    defaultFlags = _config({
      checkCredits: false,
      acceptMaxBaseFeeLimit: false,
      accrueReward: false
    });
    accrueFlags = _config({
      checkCredits: false,
      acceptMaxBaseFeeLimit: false,
      accrueReward: true
    });
    cvp = new MockCVP();
    agent = new PPAgentLite(owner, address(cvp), 3_000 ether, 3 days);
    counter = new OnlySelectorTestJob(address(agent));

    PPAgentLite.Resolver memory resolver = PPAgentLite.Resolver({
      resolverAddress: address(counter),
      resolverCalldata: new bytes(0)
    });
    PPAgentLite.RegisterJobParams memory params = PPAgentLite.RegisterJobParams({
      jobAddress: address(counter),
      jobSelector: OnlySelectorTestJob.increment.selector,
      jobOwner: alice,
      maxBaseFeeGwei: 100,
      rewardPct: 35,
      fixedReward: 10,
      useJobOwnerCredits: false,
      assertResolverSelector: false,
      jobMinCvp: 0,

      // For interval jobs
      calldataSource: CALLDATA_SOURCE_SELECTOR,
      intervalSeconds: 10
    });
    (jobKey,jobId) = agent.registerJob{ value: 1 ether }({
      params_: params,
      resolver_: resolver,
      preDefinedCalldata_: new bytes(0)
    });

    {
      cvp.transfer(keeperAdmin, 10_000 ether);

      vm.startPrank(keeperAdmin);
      cvp.approve(address(agent), 10_000 ether);
      agent.registerAsKeeper(alice, 5_000 ether);
      kid = agent.registerAsKeeper(keeperWorker, 5_000 ether);
      vm.stopPrank();

      assertEq(counter.current(), 0);
    }
  }

  function testExecWithSelector() public {
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );

    assertEq(counter.current(), 1);
  }

  function testErrExecInsufficientStake() public {
    vm.prank(owner);
    agent.setAgentParams(5_001 ether, 1, 1);

    assertEq(agent.minKeeperCvp(), 5_001 ether);
    assertEq(agent.stakeOf(kid), 5_000 ether);

    vm.expectRevert(PPAgentLite.InsufficientKeeperStake.selector);

    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
  }

  function testErrExecInsufficientJobScopedStake() public {
    vm.prank(alice);
    agent.updateJob(jobKey, 200, 55, 20, 5001 ether, 60);

    assertEq(agent.minKeeperCvp(), 3_000 ether);
    assertEq(agent.stakeOf(kid), 5_000 ether);
    assertEq(agent.jobMinKeeperCvp(jobKey), 5001 ether);

    vm.expectRevert(PPAgentLite.InsufficientJobScopedKeeperStake.selector);

    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
  }

  function testErrExecInactiveJob() public {
    vm.prank(alice);
    agent.setJobConfig(jobKey, false, false, false);

    vm.expectRevert(abi.encodeWithSelector(
        PPAgentLite.InactiveJob.selector,
        jobKey
      ));

    vm.prank(keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
  }

  function testErrExecIntervalNotReachedYet() public {
    assertEq(agent.getJob(jobKey).lastExecutionAt, 0);
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
    assertEq(agent.getJob(jobKey).lastExecutionAt, block.timestamp);
    assertEq(counter.current(), 1);

    vm.warp(block.timestamp + 3);
    vm.expectRevert(abi.encodeWithSelector(
        PPAgentLite.IntervalNotReached.selector,
        1600000000,
        10,
        1600000003
      ));

    vm.prank(keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );

    vm.warp(block.timestamp + 8);
    vm.prank(keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
    assertEq(agent.getJob(jobKey).lastExecutionAt, block.timestamp);
    assertEq(counter.current(), 2);
  }

  function testErrBaseFeeGtGasPrice() public {
    vm.fee(101 gwei);
    assertEq(block.basefee, 101 gwei);
    uint256 flags = _config({
      checkCredits: true,
      acceptMaxBaseFeeLimit: false,
      accrueReward: true
    });
    vm.expectRevert(abi.encodeWithSelector(
        PPAgentLite.BaseFeeGtGasPrice.selector,
        101 gwei,
        100 gwei
      ));
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      flags,
      kid,
      new bytes(0)
    );
  }

  function testErrNotEOA() public {
    vm.expectRevert(PPAgentLite.NonEOASender.selector);
    vm.prank(keeperWorker, bob);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
  }

  function testExecSelfPayByJobCredits() public {
    vm.fee(99 gwei);
    address jobOwner = agent.jobOwners(jobKey);

    uint256 keeperBalanceBefore = keeperWorker.balance;
    uint256 jobCreditsBefore = agent.getJob(jobKey).credits;
    uint256 ownerCreditsBefore = agent.jobOwnerCredits(jobOwner);
    uint256 compensationsBefore = agent.compensations(kid);

    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );

    uint256 keeperBalanceChange = keeperWorker.balance - keeperBalanceBefore;
    uint256 jobCreditsChange = jobCreditsBefore - agent.getJob(jobKey).credits;
    uint256 jobOwnerCreditsChange = ownerCreditsBefore - agent.jobOwnerCredits(jobOwner);
    uint256 compensationsChange = agent.compensations(kid) - compensationsBefore;

    assertEq(counter.current(), 1);
    assertApproxEqAbs(0.01204694875 ether, keeperBalanceChange, 0.0001 ether);
    assertEq(keeperBalanceChange, jobCreditsChange);

    assertEq(compensationsChange, 0);
    assertEq(jobOwnerCreditsChange, 0);
  }

  function testExecAccrueRewardByJobCredits() public {
    vm.fee(99 gwei);
    address jobOwner = agent.jobOwners(jobKey);

    uint256 keeperBalanceBefore = keeperWorker.balance;
    uint256 jobCreditsBefore = agent.getJob(jobKey).credits;
    uint256 compensationsBefore = agent.compensations(kid);
    uint256 ownerCreditsBefore = agent.jobOwnerCredits(jobOwner);

    assertEq(
      bytes32(agent.getJobRaw(jobKey)),
      bytes32(0x0000000000000a000000000a002300640000000de0b6b3a7640000d09de08a01)
    );

    // Exec #1
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      accrueFlags,
      kid,
      new bytes(0)
    );

    uint256 keeperBalanceChange = keeperWorker.balance - keeperBalanceBefore;
    uint256 jobCreditsChange = jobCreditsBefore - agent.getJob(jobKey).credits;
    uint256 jobOwnerCreditsChange = ownerCreditsBefore - agent.jobOwnerCredits(jobOwner);
    uint256 compensationsChange = agent.compensations(kid) - compensationsBefore;

    assertEq(counter.current(), 1);

    assertApproxEqAbs(0.01204694875 ether, jobCreditsChange, 0.0001 ether);
    assertEq(compensationsChange, jobCreditsChange);

    assertEq(keeperBalanceChange, 0);
    assertEq(jobOwnerCreditsChange, 0);

    // Exec #2
    vm.warp(block.timestamp + 31);
    compensationsBefore = agent.compensations(kid);
    jobCreditsBefore = agent.getJob(jobKey).credits;
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      accrueFlags,
      kid,
      new bytes(0)
    );
    compensationsChange = agent.compensations(kid) - compensationsBefore;
    jobCreditsChange = jobCreditsBefore - agent.getJob(jobKey).credits;
    assertEq(compensationsChange, jobCreditsChange);
  }

  function testExecSelfPayByJobOwnerCredits() public {
    vm.fee(99 gwei);
    address jobOwner = agent.jobOwners(jobKey);

    vm.deal(alice, 2 ether);
    vm.prank(alice);
    agent.depositJobOwnerCredits{value: 1 ether }(alice);

    vm.prank(alice);
    agent.setJobConfig(jobKey, true, true, false);

    uint256 keeperBalanceBefore = keeperWorker.balance;
    uint256 jobCreditsBefore = agent.getJob(jobKey).credits;
    uint256 ownerCreditsBefore = agent.jobOwnerCredits(jobOwner);
    uint256 compensationsBefore = agent.compensations(kid);

    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );

    uint256 keeperBalanceChange = keeperWorker.balance - keeperBalanceBefore;
    uint256 jobCreditsChange = jobCreditsBefore - agent.getJob(jobKey).credits;
    uint256 jobOwnerCreditsChange = ownerCreditsBefore - agent.jobOwnerCredits(jobOwner);
    uint256 compensationsChange = agent.compensations(kid) - compensationsBefore;

    assertEq(counter.current(), 1);
    assertApproxEqAbs(0.01204694875 ether, keeperBalanceChange, 0.0001 ether);
    assertEq(keeperBalanceChange, jobOwnerCreditsChange);

    assertEq(compensationsChange, 0);
    assertEq(jobCreditsChange, 0);
  }

  function testFailExecJobCreditsNotEnoughFunds() public {
    vm.fee(99 gwei);
    vm.prank(alice);
    agent.withdrawJobCredits(jobKey, alice, 0.9999 ether);
    assertEq(agent.getJob(jobKey).credits, 0.0001 ether);

    // TODO: assert only revert+error selector
    // vm.expectRevert(abi.encodeWithSelector(PPAgentLite.InsufficientJobCredits.selector))
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
  }

  function testFailExecJobOwnerCreditsNotFunds() public {
    vm.fee(99 gwei);
    vm.prank(alice);
    agent.setJobConfig(jobKey, true, true, false);

    // TODO: assert only revert+error selector
    // vm.expectRevert(abi.encodeWithSelector(PPAgentLite.InsufficientJobOwnerCredits.selector))
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      accrueFlags,
      kid,
      new bytes(0)
    );
  }
}
