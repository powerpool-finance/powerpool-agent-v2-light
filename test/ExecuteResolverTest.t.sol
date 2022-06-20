// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentLite.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";
import "./jobs/IntervalResolverSimpleCalldataJob.sol";
import "./jobs/NoCalldataTestJob.sol";
import "./jobs/OnlySelectorTestJob.sol";
import "./jobs/SimpleCalldataTestJob.sol";
import "./jobs/ComplexCalldataTestJob.sol";
import "./jobs/SimpleCalldataIntervalTestJob.sol";

contract ExecuteResolverTest is TestHelper {
  MockCVP internal cvp;
  PPAgentLite internal agent;
  ICounter internal job;

  bytes32 internal jobKey;
  uint256 internal jobId;
  uint256 internal defaultFlags;
  uint256 internal kid;

  function setUp() public override {
    defaultFlags = _config({
      checkCredits: false,
      acceptMaxBaseFeeLimit: false,
      accrueReward: false
    });
    cvp = new MockCVP();
    agent = new PPAgentLite(bob, address(cvp), 3_000 ether, 3 days);

    {
      cvp.transfer(keeperAdmin, 10_000 ether);
      vm.prank(keeperAdmin);
      cvp.approve(address(agent), 10_000 ether);
      vm.prank(keeperAdmin);
      agent.registerAsKeeper(keeperWorker, 5_000 ether);
      vm.prank(keeperAdmin);
      kid = agent.registerAsKeeper(keeperWorker, 5_000 ether);
    }
  }

  function _setupJob(address job_, bytes4 selector_, bool assertSelector_) internal {
    PPAgentLite.Resolver memory resolver = PPAgentLite.Resolver({
      resolverAddress: job_,
      resolverCalldata: abi.encode("myPass")
    });
    PPAgentLite.RegisterJobParams memory params = PPAgentLite.RegisterJobParams({
      jobAddress: job_,
      jobSelector: selector_,
      jobOwner: alice,
      maxBaseFeeGwei: 100,
      rewardPct: 35,
      fixedReward: 10,
      useJobOwnerCredits: false,
      assertResolverSelector: assertSelector_,
      jobMinCvp: 0,

      // For interval jobs
      calldataSource: CALLDATA_SOURCE_RESOLVER,
      intervalSeconds: 0
    });
    (jobKey,jobId) = agent.registerJob{ value: 1 ether }({
      params_: params,
      resolver_: resolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  function executeJob() internal {
    (bool ok, bytes memory cd) = job.myResolver("myPass");
    assertEq(ok, true);

    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(job),
      jobId,
      defaultFlags,
      kid,
      cd
    );
  }

  // ZERO CALLDATA

  function testExecResolverZeroCalldataNoCheck() public {
    job = new NoCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), ZERO_SELECTOR, false);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  // selector check should not work for 0-length calldata
  function testExecResolverZeroCalldataWithCheck() public {
    job = new NoCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), ZERO_SELECTOR, true);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  // ONLY SELECTOR CALLDATA

  function testExecResolverSelectorCalldataNoCheck() public {
    job = new OnlySelectorTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), OnlySelectorTestJob.increment.selector, false);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testExecResolverSelectorCalldataWithCheck() public {
    job = new OnlySelectorTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), OnlySelectorTestJob.increment.selector, true);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testErrExecResolverSelectorCalldataWithCheckWrongSelector() public {
    job = new OnlySelectorTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), OnlySelectorTestJob.increment2.selector, true);

    (bool ok, bytes memory cd) = job.myResolver("myPass");
    assertEq(ok, true);

    vm.expectRevert(0x84fb8275/*PPAgentLite.SelectorCheckFailed.selector*/);
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(job),
      jobId,
      defaultFlags,
      kid,
      cd
    );
  }

  // SIMPLE CALLDATA

  function testExecResolverSimpleCalldataNoCheck() public {
    job = new SimpleCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), SimpleCalldataTestJob.increment.selector, false);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testExecResolverSimpleCalldataWithCheck() public {
    job = new SimpleCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), SimpleCalldataTestJob.increment.selector, true);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testErrExecResolverSimpleCalldataWithCheckWrongSelector() public {
    job = new SimpleCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), SimpleCalldataTestJob.increment2.selector, true);

    (bool ok, bytes memory cd) = job.myResolver("myPass");
    assertEq(ok, true);

    vm.expectRevert(0x84fb8275/*PPAgentLite.SelectorCheckFailed.selector*/);
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(job),
      jobId,
      defaultFlags,
      kid,
      cd
    );
  }

  // COMPLEX CALLDATA

  function testExecResolverComplexCalldataNoCheck() public {
    job = new ComplexCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), ComplexCalldataTestJob.increment.selector, false);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testExecResolverComplexCalldataWithCheck() public {
    job = new ComplexCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), ComplexCalldataTestJob.increment.selector, true);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testErrExecResolverComplexCalldataWithCheckWrongSelector() public {
    job = new ComplexCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), ComplexCalldataTestJob.increment2.selector, true);

    (bool ok, bytes memory cd) = job.myResolver("myPass");
    assertEq(ok, true);

    vm.expectRevert(0x84fb8275/*PPAgentLite.SelectorCheckFailed.selector*/);
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(job),
      jobId,
      defaultFlags,
      kid,
      cd
    );
  }

  // INTERVAL

  function testErrExecResolverTooEarly() public {
    job = new SimpleCalldataIntervalTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), SimpleCalldataIntervalTestJob.increment.selector, false);

    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    (bool ok, bytes memory cd) = job.myResolver("myPass");
    assertEq(ok, false);

    // execute #2
    // second call is too early
    vm.expectRevert(bytes("interval"));
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(job),
      jobId,
      defaultFlags,
      kid,
      cd
    );
  }
}
