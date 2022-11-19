// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "./TestHelper.sol";
import "./jobs/NoCalldataTestJob.sol";
import "./jobs/OnlySelectorTestJob.sol";
import "./jobs/SimpleCalldataTestJob.sol";
import "./jobs/ComplexCalldataTestJob.sol";

contract ExecutePDCalldataTest is TestHelper {
  ICounter internal job;

  bytes32 internal jobKey;
  uint256 internal jobId;
  uint256 internal defaultFlags;
  uint256 internal kid;

  function setUp() public override {
    defaultFlags = _config({
      acceptMaxBaseFeeLimit: false,
      accrueReward: false
    });
    cvp = new MockCVP();
    agent = new PPAgentV2(bob, address(cvp), 3_000 ether, 3 days);

    {
      cvp.transfer(keeperAdmin, 5_000 ether);
      vm.prank(keeperAdmin);
      cvp.approve(address(agent), 5_000 ether);
      vm.prank(keeperAdmin);
      kid = agent.registerAsKeeper(keeperWorker, 5_000 ether);
    }
  }

  function _setupJob(address job_, bytes memory preDefinedCalldata_) internal {
    PPAgentV2.Resolver memory resolver = IPPAgentV2Viewer.Resolver({
      resolverAddress: address(0),
      resolverCalldata: new bytes(0)
    });
    PPAgentV2.RegisterJobParams memory params = PPAgentV2.RegisterJobParams({
      jobAddress: job_,
      jobSelector: NON_ZERO_SELECTOR,
      maxBaseFeeGwei: 100,
      rewardPct: 35,
      fixedReward: 10,
      useJobOwnerCredits: false,
      assertResolverSelector: false,
      jobMinCvp: 0,

      // For interval jobs
      calldataSource: CALLDATA_SOURCE_PRE_DEFINED,
      intervalSeconds: 10
    });
    vm.prank(alice);
    vm.deal(alice, 10 ether);
    (jobKey,jobId) = agent.registerJob{ value: 1 ether }({
      params_: params,
      resolver_: resolver,
      preDefinedCalldata_: preDefinedCalldata_
    });
  }

  modifier zeroCalldataJob() {
    job = new NoCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), new bytes(0));
    _;
  }

  modifier selectorCalldataJob() {
    job = new OnlySelectorTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), abi.encode(OnlySelectorTestJob.increment.selector));
    _;
  }

  modifier simpleCalldataJob() {
    job = new SimpleCalldataTestJob(address(agent));
    assertEq(job.current(), 0);
    _setupJob(address(job), abi.encodeWithSelector(
        SimpleCalldataTestJob.increment.selector,
        5, true, uint24(42), "d-value"
      ));
    _;
  }

  modifier complexCalldataJob() {
    job = new ComplexCalldataTestJob(address(agent));
    assertEq(job.current(), 0);

    string[] memory b = new string[](2);
    b[0] = "b-value-0";
    b[1] = "b-value-1";

    ComplexCalldataTestJob.Params memory c;
    c.v1.l21 = new bool[](3);
    c.v1.l21[0] = true;
    c.v1.l21[1] = false;
    c.v1.l21[2] = true;

    c.v2[0] = new bool[][](3);
    c.v2[0][0] = new bool[](5);
    c.v2[0][1] = new bool[](6);
    c.v2[0][2] = new bool[](7);

    c.v2[0][2][5] = true;

    c.v2[1] = new bool[][](4);

    _setupJob(address(job), abi.encodeWithSelector(
        ComplexCalldataTestJob.increment.selector,
        uint24(42), b, c
      ));
    _;
  }

  function executeJob() internal {
    vm.prank(keeperWorker, keeperWorker);
    _callExecuteHelper(
      agent,
      address(job),
      jobId,
      defaultFlags,
      kid,
      new bytes(0)
    );
  }

  function testExecPDCalldataZeroCalldata() public zeroCalldataJob {
    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testExecPDCalldataSelectorCalldata() public selectorCalldataJob {
    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testExecPDCalldataSimpleCalldata() public simpleCalldataJob {
    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }

  function testExecPDCalldataComplexCalldata() public complexCalldataJob {
    // execute #1
    executeJob();
    assertEq(job.current(), 1);

    // execute #2
    vm.warp(block.timestamp + 11);
    executeJob();
    assertEq(job.current(), 2);
  }
}
