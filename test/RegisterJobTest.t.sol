// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "../contracts/jobs/CounterJob.sol";
import "../lib/forge-std/src/console.sol";
import "./TestHelper.sol";
import "../contracts/PPAgentV2Lens.sol";

contract RegisterJob is TestHelper {
  address internal job1 = address(0x1111111111111111111111111111111111111111);
  address internal job2 = address(0x2222222222222222222222222222222222222222);
  address internal job3 = address(0x3333333333333333333333333333333333333333);

  PPAgentV2Lens internal lens;
  CounterJob internal counter;

  PPAgentV2.RegisterJobParams internal params1;
  PPAgentV2.RegisterJobParams internal params2;
  PPAgentV2.RegisterJobParams internal params3;
  PPAgentV2.Resolver internal emptyResolver;
  PPAgentV2.Resolver internal resolver1;

  function setUp() public override {
    cvp = new MockCVP();
    agent = new PPAgentV2(owner, address(cvp), 3_000 ether, 3 days);
    lens = new PPAgentV2Lens(owner, address(cvp), 3_000 ether, 3 days);
    cvp.transfer(alice, 10_000 ether);
    address[] memory agents = new address[](1);
    agents[0] = address(agent);
    counter = new CounterJob(agents);

    params1 = PPAgentV2.RegisterJobParams({
      jobAddress: job1,
      jobSelector: CounterJob.increment.selector,
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
    params2 = PPAgentV2.RegisterJobParams({
      jobAddress: job2,
      jobSelector: CounterJob.increment.selector,
      maxBaseFeeGwei: 100,
      rewardPct: 35,
      fixedReward: 10,
      useJobOwnerCredits: false,
      assertResolverSelector: false,
      jobMinCvp: 30,

      // For interval jobs
      calldataSource: CALLDATA_SOURCE_PRE_DEFINED,
      intervalSeconds: 180 days
    });
    params3 = PPAgentV2.RegisterJobParams({
      jobAddress: job3,
      jobSelector: CounterJob.increment.selector,
      maxBaseFeeGwei: 100,
      rewardPct: 35,
      fixedReward: 10,
      useJobOwnerCredits: false,
      assertResolverSelector: true,
      jobMinCvp: 0,

      // For interval jobs
      calldataSource: CALLDATA_SOURCE_RESOLVER,
      intervalSeconds: 0
    });
    emptyResolver = PPAgentV2.Resolver({
      resolverAddress: address(0),
      resolverCalldata: new bytes(0)
    });
    resolver1 = PPAgentV2.Resolver({
      resolverAddress: job1,
      resolverCalldata: hex"313373"
    });
  }

  function testShouldIncrementIdForAddress() public {
    assertEq(agent.jobNextIds(job1), 0);

    (, uint256 jobId) = agent.registerJob({
      params_: params1,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
    assertEq(jobId, 0);
    assertEq(agent.jobNextIds(job1), 1);

    (,jobId) = agent.registerJob({
      params_: params1,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
    assertEq(jobId, 1);
    assertEq(agent.jobNextIds(job1), 2);

    (,jobId) = agent.registerJob({
      params_: params1,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
    assertEq(jobId, 2);
    assertEq(agent.jobNextIds(job1), 3);

    // Addrss #2
    assertEq(agent.jobNextIds(job2), 0);
    (,jobId) = agent.registerJob({
      params_: params2,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
    assertEq(jobId, 0);
    assertEq(agent.jobNextIds(job2), 1);
  }

  function testShouldGenerateCorrectJobKey() public {
    (bytes32 jobKey, uint256 jobId) = agent.registerJob({
      params_: params1,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
    assertEq(jobId, 0);
    assertEq(agent.getJobKey(job1, jobId), jobKey);

    (jobKey, jobId) = agent.registerJob({
      params_: params1,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
    assertEq(jobId, 1);
    assertEq(agent.getJobKey(job1, jobId), jobKey);
  }

  function testShouldStoreJobDetailsWithinASingleSlot() public {
    vm.fee(25 gwei);
    (bytes32 jobKey,) = agent.registerJob{value: 1 ether}({
      params_: params1,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
    // TODO: assert lastExecutionAt too
    uint256 job = agent.getJobRaw(jobKey);
    assertEq(job, 0x0000000000000a000000000a002300640000000de0b6b3a7640000d09de08a01);
  }

  function testRegisterIntervalJobWithSelector() public {
    vm.prank(bob);
    (bytes32 jobKey,) = agent.registerJob({
      params_: params1,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });

    (bool ok, bytes memory result) = address(agent).staticcall(
      abi.encodeWithSelector(PPAgentV2.getJob.selector, jobKey)
    );
    assertEq(ok, true);
    assertEq(result.length, 576);

    PPAgentV2.Job memory job = _jobDetails(jobKey);
    assertEq(job.selector, CounterJob.increment.selector);
    assertEq(job.credits, 0);
    assertEq(job.maxBaseFeeGwei, 100);
    assertEq(job.rewardPct, 35);
    assertEq(job.fixedReward, 10);
    assertEq(job.calldataSource, CALLDATA_SOURCE_SELECTOR);
    assertEq(job.intervalSeconds, 10);
    assertEq(job.lastExecutionAt, 0);

    (
      bool isActive,
      bool useJobOwnerCredits,
      bool assertResolverSelector,
      bool checkKeeperMinCvpDeposit
    ) = lens.parseConfigPure(job.config);
    assertEq(isActive, true);
    assertEq(useJobOwnerCredits, false);
    assertEq(assertResolverSelector, false);
    assertEq(checkKeeperMinCvpDeposit, false);
    assertEq(lens.isJobActivePure(agent.getJobRaw(jobKey)), true);

    assertEq(_jobOwner(jobKey), bob);
    assertEq(agent.jobOwnerCredits(bob), 0);
  }

  function testErrJobWithCvpAddress() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.jobAddress = address(cvp);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.InvalidJobAddress.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  function testErrJobWithSelectorMissingInterval() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.intervalSeconds = 0;

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.JobShouldHaveInterval.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  function testErrJobWithSelectorMissingAddress() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.jobAddress = address(0);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingJobAddress.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  function testErrJobWithSelectorMissingMaxGasFee() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.maxBaseFeeGwei = 0;

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingMaxBaseFeeGwei.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  function testJobWithSelectorNoFixedReward() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.fixedReward = 0;

    (bytes32 jobKey,) = agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });

    PPAgentV2.Job memory job = _jobDetails(jobKey);
    assertEq(lens.isJobActivePure(agent.getJobRaw(jobKey)), true);
    assertEq(job.fixedReward, 0);
  }

  function testErrJobWithSelectorNoFixedNorPremium() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.fixedReward = 0;
    params.rewardPct = 0;

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.NoFixedNorPremiumPctReward.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  function testErrJobInvalidCalldataSource() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.calldataSource = 3;

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.InvalidCalldataSource.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  // PRE-DEFINED CALLDATA

  function testJobWithPDCalldata() public {
    PPAgentV2.RegisterJobParams memory params = params2;

    (bytes32 jobKey,) = agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: hex"313373"
    });

    assertEq(_jobPreDefinedCalldata(jobKey), hex"313373");

    PPAgentV2.Job memory job = _jobDetails(jobKey);
    assertEq(lens.isJobActivePure(agent.getJobRaw(jobKey)), true);
    assertEq(job.calldataSource, CALLDATA_SOURCE_PRE_DEFINED);

    assertEq(
      bytes32(agent.getJobRaw(jobKey)),
      bytes32(0x00000000ed4e00010000000a0023006400000000000000000000000000000009)
    );
  }

  function testJobWithMinCvpDeposit() public {
    (bytes32 jobKey,) = agent.registerJob({
      params_: params2,
      resolver_: emptyResolver,
      preDefinedCalldata_: hex"313373"
    });

    PPAgentV2.Job memory job = _jobDetails(jobKey);

    (
      bool isActive,
      bool useJobOwnerCredits,
      bool assertResolverSelector,
      bool checkKeeperMinCvpDeposit
    ) = lens.parseConfigPure(job.config);
    assertEq(isActive, true);
    assertEq(useJobOwnerCredits, false);
    assertEq(assertResolverSelector, false);
    assertEq(checkKeeperMinCvpDeposit, true);
    assertEq(_jobMinKeeperCvp(jobKey), 30);
  }

  function testErrJobWithPDCalldataMissingInterval() public {
    PPAgentV2.RegisterJobParams memory params = params2;
    params.intervalSeconds = 0;

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.JobShouldHaveInterval.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  // RESOLVER

  function testJobWithResolverNoInterval() public {
    PPAgentV2.RegisterJobParams memory params = params3;

    (bytes32 jobKey,) = agent.registerJob({
      params_: params,
      resolver_: resolver1,
      preDefinedCalldata_: hex"313373"
    });

    assertEq(_jobPreDefinedCalldata(jobKey), new bytes(0));

    PPAgentV2.Job memory job = _jobDetails(jobKey);
    assertEq(job.selector, bytes4(0xd09de08a));
    assertEq(job.intervalSeconds, 0);
    assertEq(job.calldataSource, CALLDATA_SOURCE_RESOLVER);

    (
      bool isActive,
      bool useJobOwnerCredits,
      bool assertResolverSelector,
      bool checkKeeperMinCvpDeposit
    ) = lens.parseConfigPure(job.config);
    assertEq(isActive, true);
    assertEq(useJobOwnerCredits, false);
    assertEq(assertResolverSelector, true);
    assertEq(checkKeeperMinCvpDeposit, false);
    assertEq(lens.isJobActivePure(agent.getJobRaw(jobKey)), true);

    PPAgentV2.Resolver memory res = _jobResolver(jobKey);
    assertEq(res.resolverAddress, job1);
    assertEq(res.resolverCalldata, hex"313373");

    assertEq(
      bytes32(agent.getJobRaw(jobKey)),
      bytes32(0x00000000000000020000000a002300640000000000000000000000d09de08a05)
    );
  }

  function testJobWithResolverWithInterval() public {
    PPAgentV2.RegisterJobParams memory params = params3;
    params.intervalSeconds = 1_000;

    (bytes32 jobKey,) = agent.registerJob({
      params_: params,
      resolver_: resolver1,
      preDefinedCalldata_: hex"313373"
    });

    PPAgentV2.Job memory job = _jobDetails(jobKey);
    assertEq(lens.isJobActivePure(agent.getJobRaw(jobKey)), true);
    assertEq(job.selector, bytes4(0xd09de08a));
    assertEq(job.intervalSeconds, 1_000);
    assertEq(job.calldataSource, CALLDATA_SOURCE_RESOLVER);
  }

  function testErrJobWithResolverMissingAddress() public {
    PPAgentV2.RegisterJobParams memory params = params3;
    PPAgentV2.Resolver memory resolver = resolver1;
    resolver.resolverAddress = address(0);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingResolverAddress.selector)
    );
    agent.registerJob({
      params_: params,
      resolver_: resolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  // CREDITS

  function testShouldAllowDepositToTheJobBalanceNoFee() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.useJobOwnerCredits = false;

    vm.prank(bob);
    vm.deal(bob, 2 ether);
    (bytes32 jobKey,) = agent.registerJob{ value: 1.5 ether }({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });

    PPAgentV2.Job memory job = _jobDetails(jobKey);
    assertEq(job.credits, 1.5 ether);
    assertEq(agent.jobOwnerCredits(bob), 0);
  }

  function testShouldAllowDepositToTheJobBalanceWithFee() public {
    vm.prank(owner);
    agent.setAgentParams(3_000 ether, 30 days, 4e4);

    PPAgentV2.RegisterJobParams memory params = params1;
    params.useJobOwnerCredits = false;

    (bytes32 jobKey,) = agent.registerJob{ value: 10 ether }({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });

    assertEq(_jobDetails(jobKey).credits, 9.6 ether);
    (,,uint256 feeTotal,) = agent.getConfig();
    assertEq(feeTotal, 0.4 ether);
  }

  function testShouldAllowDepositToTheOwnerBalanceNoFee() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.useJobOwnerCredits = true;

    vm.prank(bob);
    vm.deal(bob, 2 ether);
    (bytes32 jobKey,) = agent.registerJob{ value: 1.5 ether }({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });

    PPAgentV2.Job memory job = _jobDetails(jobKey);
    assertEq(job.credits, 0);
    assertEq(agent.jobOwnerCredits(bob), 1.5 ether);
  }

  function testShouldAllowDepositToTheOwnerBalanceWithFee() public {
    vm.prank(owner);
    agent.setAgentParams(3_000 ether, 30 days, 4e4);

    PPAgentV2.RegisterJobParams memory params = params1;
    params.useJobOwnerCredits = true;

    vm.prank(bob);
    vm.deal(bob, 10 ether);
    (bytes32 jobKey,) = agent.registerJob{ value: 10 ether }({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });

    assertEq(_jobDetails(jobKey).credits, 0);
    assertEq(agent.jobOwnerCredits(bob), 9.6 ether);
    (,,uint256 feeTotal,) = agent.getConfig();
    assertEq(feeTotal, 0.4 ether);
  }

  function testErrDepositToTheJobBalanceOverflow() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.useJobOwnerCredits = false;

    vm.expectRevert(PPAgentV2.CreditsDepositOverflow.selector);
    vm.deal(alice, type(uint256).max);
    vm.prank(alice);
    agent.registerJob{ value: uint256(type(uint96).max) + 1 }({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }

  function testErrDepositToTheOwnerBalanceOverflow() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.useJobOwnerCredits = true;

    vm.expectRevert(PPAgentV2.CreditsDepositOverflow.selector);
    vm.deal(alice, type(uint256).max);
    vm.prank(alice);
    agent.registerJob{ value: uint256(type(uint96).max) + 1 }({
      params_: params,
      resolver_: emptyResolver,
      preDefinedCalldata_: new bytes(0)
    });
  }
}
