// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./jobs/OnlySelectorTestJob.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";
import "forge-std/Vm.sol";

contract ExecuteSelectorTest is TestHelper {
  event Execute(bytes32 indexed jobKey, address indexed job, bool indexed success, uint256 gasUsed, uint256 baseFee, uint256 gasPrice, uint256 compensation);

  OnlySelectorTestJob internal counter;

  bytes32 internal jobKey;
  uint256 internal jobId;
  uint256 internal defaultFlags;
  uint256 internal accrueFlags;
  uint256 internal kid;

  function setUp() public override {
    defaultFlags = _config({
      acceptMaxBaseFeeLimit: false,
      accrueReward: false
    });
    accrueFlags = _config({
      acceptMaxBaseFeeLimit: false,
      accrueReward: true
    });
    cvp = new MockCVP();
    agent = new PPAgentV2(owner, address(cvp), 3_000 ether, 3 days);
    counter = new OnlySelectorTestJob(address(agent));

    PPAgentV2.Resolver memory resolver = PPAgentV2.Resolver({
      resolverAddress: address(counter),
      resolverCalldata: new bytes(0)
    });
    PPAgentV2.RegisterJobParams memory params = PPAgentV2.RegisterJobParams({
      jobAddress: address(counter),
      jobSelector: OnlySelectorTestJob.increment.selector,
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
    vm.prank(alice);
    vm.deal(alice, 10 ether);
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
    assertEq(_stakeOf(kid), 5_000 ether);

    vm.expectRevert(PPAgentV2.InsufficientKeeperStake.selector);

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
    assertEq(_stakeOf(kid), 5_000 ether);
    assertEq(agent.jobMinKeeperCvp(jobKey), 5001 ether);

    vm.expectRevert(PPAgentV2.InsufficientJobScopedKeeperStake.selector);

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
        PPAgentV2.InactiveJob.selector,
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
        PPAgentV2.IntervalNotReached.selector,
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
      acceptMaxBaseFeeLimit: false,
      accrueReward: true
    });
    vm.expectRevert(abi.encodeWithSelector(
        PPAgentV2.BaseFeeGtGasPrice.selector,
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

  function testAcceptBaseFeeGtGasPrice() public {
    vm.fee(500 gwei);
    assertEq(block.basefee, 500 gwei);
    assertEq(agent.getJob(jobKey).maxBaseFeeGwei, 100);
    uint256 flags = _config({
      acceptMaxBaseFeeLimit: true,
      accrueReward: false
    });

    uint256 workerBalanceBefore = keeperWorker.balance;

    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      flags,
      kid,
      new bytes(0)
    );

    assertApproxEqAbs(keeperWorker.balance - workerBalanceBefore, agent.calculateCompensationPure({
      rewardPct_: 35,
      fixedReward_: 10,
      blockBaseFee_: 100 gwei,
      gasUsed_: 34070
    }), 0.0001 ether);
  }

  function testAcceptBaseFeeLtGasPrice() public {
    vm.fee(10 gwei);
    assertEq(block.basefee, 10 gwei);
    assertEq(agent.getJob(jobKey).maxBaseFeeGwei, 100);
    uint256 flags = _config({
      acceptMaxBaseFeeLimit: true,
      accrueReward: false
    });

    uint256 workerBalanceBefore = keeperWorker.balance;

    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(counter),
      jobId,
      flags,
      kid,
      new bytes(0)
    );

    assertApproxEqAbs(keeperWorker.balance - workerBalanceBefore, agent.calculateCompensationPure({
      rewardPct_: 35,
      fixedReward_: 10,
      blockBaseFee_: 10 gwei,
      gasUsed_: 34070
    }), 0.0001 ether);
  }

  function testErrNotEOA() public {
    vm.expectRevert(PPAgentV2.NonEOASender.selector);
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
    uint256 compensationsBefore = _compensationOf(kid);

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
    uint256 compensationsChange = _compensationOf(kid) - compensationsBefore;

    assertEq(counter.current(), 1);
    assertApproxEqAbs(0.01256604040 ether, keeperBalanceChange, 0.0001 ether);
    assertEq(keeperBalanceChange, jobCreditsChange);

    assertEq(compensationsChange, 0);
    assertEq(jobOwnerCreditsChange, 0);
  }

  function testExecAccrueRewardByJobCredits() public {
    vm.fee(99 gwei);
    address jobOwner = agent.jobOwners(jobKey);

    uint256 keeperBalanceBefore = keeperWorker.balance;
    uint256 jobCreditsBefore = agent.getJob(jobKey).credits;
    uint256 compensationsBefore = _compensationOf(kid);
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
    uint256 compensationsChange = _compensationOf(kid) - compensationsBefore;

    assertEq(counter.current(), 1);

    assertApproxEqAbs(0.0125660404 ether, jobCreditsChange, 0.0001 ether);
    assertEq(compensationsChange, jobCreditsChange);

    assertEq(keeperBalanceChange, 0);
    assertEq(jobOwnerCreditsChange, 0);

    // Exec #2
    vm.warp(block.timestamp + 31);
    compensationsBefore = _compensationOf(kid);
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
    compensationsChange = _compensationOf(kid) - compensationsBefore;
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
    uint256 compensationsBefore = _compensationOf(kid);

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
    uint256 compensationsChange = _compensationOf(kid) - compensationsBefore;

    assertEq(counter.current(), 1);
    assertApproxEqAbs(0.0125660404 ether, keeperBalanceChange, 0.0001 ether);
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
    // vm.expectRevert(abi.encodeWithSelector(PPAgentV2.InsufficientJobCredits.selector))
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
    // vm.expectRevert(abi.encodeWithSelector(PPAgentV2.InsufficientJobOwnerCredits.selector))
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
