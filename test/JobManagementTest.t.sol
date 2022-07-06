// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../contracts/PPAgentV2.sol";
import "./mocks/MockCVP.sol";
import "../contracts/PPAgentV2Lens.sol";
import "./TestHelper.sol";

contract JobManagementTest is TestHelper {
  event DepositJobCredits(bytes32 indexed jobKey, address indexed depositor, uint256 amount, uint256 fee);
  event WithdrawJobCredits(bytes32 indexed jobKey, address indexed owner, address indexed to, uint256 amount);
  event JobTransfer(bytes32 indexed jobKey, address indexed from, address indexed to);
  event SetJobConfig(bytes32 indexed jobKey, bool isActive_, bool useJobOwnerCredits_, bool assertResolverSelector_);
  event SetJobResolver(bytes32 indexed jobKey, address resolverAddress, bytes resolverCalldata);
  event SetJobPreDefinedCalldata(bytes32 indexed jobKey, bytes preDefinedCalldata);
  event SetUseJobOwnerCredits(bytes32 indexed jobKey, bool useJobOwnerCredits);
  event JobUpdate(
    bytes32 indexed jobKey,
    uint256 maxBaseFeeGwei,
    uint256 rewardPct,
    uint256 fixedReward,
    uint256 jobMinCvp,
    uint256 intervalSeconds
  );

  MockCVP internal cvp;
  PPAgentV2 internal agent;
  PPAgentV2Lens internal lens;
  bytes32 internal jobKey;

  PPAgentV2.RegisterJobParams internal params1;
  PPAgentV2.Resolver internal resolver1;

  modifier jobWithResolverCalldataSource() {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.calldataSource = CALLDATA_SOURCE_RESOLVER;
    (jobKey,) = agent.registerJob(params, resolver1, new bytes(0));
    _;
  }

  modifier jobWithPreDefinedCalldataSource() {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.calldataSource = CALLDATA_SOURCE_PRE_DEFINED;
    (jobKey,) = agent.registerJob(params, resolver1, new bytes(0));
    _;
  }

  function setUp() public override {
    vm.deal(alice, 100 ether);
    cvp = new MockCVP();
    agent = new PPAgentV2(owner, address(cvp), 3_000 ether, 3 days);
    lens = new PPAgentV2Lens(owner, address(cvp), 3_000 ether, 3 days);
    vm.deal(address(agent), 1000 ether);
    cvp.transfer(alice, 10_000 ether);
    params1 = PPAgentV2.RegisterJobParams({
      jobAddress: alice,
      jobSelector: hex"00000001",
      jobOwner: alice,
      maxBaseFeeGwei: 100,
      rewardPct: 35,
      fixedReward: 10,
      useJobOwnerCredits: false,
      assertResolverSelector: false,
      jobMinCvp: 0,

      // For interval jobs
      calldataSource: CALLDATA_SOURCE_SELECTOR,
      intervalSeconds: 15
    });
    resolver1 = PPAgentV2.Resolver({
      resolverAddress: address(1),
      resolverCalldata: new bytes(0)
    });
    (jobKey,) = agent.registerJob({
      params_: params1,
      resolver_: resolver1,
      preDefinedCalldata_: new bytes(0)
    });
  }

  // depositJobCredits()

  function testAddJobCredits() public {
    // 1st deposit
    uint256 aliceBalanceBefore = alice.balance;
    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobCredits(jobKey, alice, 1.2 ether, 0);
    vm.prank(alice);
    agent.depositJobCredits{ value: 1.2 ether}(jobKey);

    PPAgentV2.Job memory job = agent.getJob(jobKey);
    assertEq(job.credits, 1.2 ether);

    assertEq(alice.balance, aliceBalanceBefore - 1.2 ether);

    // 2nd deposit
    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobCredits(jobKey, alice, 3.6 ether, 0);
    vm.prank(alice);
    agent.depositJobCredits{ value: 3.6 ether}(jobKey);

    job = agent.getJob(jobKey);
    assertEq(job.credits, 4.8 ether);

    assertEq(alice.balance, aliceBalanceBefore - 4.8 ether);
  }

  function testAddJobCreditsMaxOneStep() public {
    uint256 maxAmount = type(uint88).max - 1;
    vm.deal(alice, maxAmount);
    uint256 aliceBalanceBefore = alice.balance;

    assertEq(agent.getJob(jobKey).credits, 0);

    vm.prank(alice);
    agent.depositJobCredits{ value: maxAmount }(jobKey);

    assertEq(agent.getJob(jobKey).credits, maxAmount);
    assertEq(alice.balance, aliceBalanceBefore - maxAmount);
  }

  function testAddJobCreditsWithFee() public {
    vm.prank(owner);
    agent.setAgentParams(3_000 ether, 30 days, 4e4);

    assertEq(agent.getJob(jobKey).credits, 0);

    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobCredits(jobKey, alice, 9.6 ether, 0.4 ether);
    vm.prank(alice);
    agent.depositJobCredits{value: 10 ether}(jobKey);

    assertEq(agent.getJob(jobKey).credits, 9.6 ether);
    assertEq(agent.feeTotal(), 0.4 ether);

    vm.expectEmit(true, true, false, true, address(agent));
    emit DepositJobCredits(jobKey, alice, 19.2 ether, 0.8 ether);
    vm.prank(alice);
    agent.depositJobCredits{value: 20 ether}(jobKey);

    assertEq(agent.getJob(jobKey).credits, 28.8 ether);
    assertEq(agent.feeTotal(), 1.2 ether);
  }

  function testErrAddJobCreditsZeroDeposit() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingDeposit.selector)
    );

    vm.prank(alice);
    agent.depositJobCredits{ value: 0 ether}(jobKey);
  }

  function testErrAddJobCreditsNoOwner() public {
    bytes32 fakeJobKey = bytes32(uint256(123));
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.JobWithoutOwner.selector)
    );

    vm.prank(alice);
    agent.depositJobCredits{ value: 1 ether}(fakeJobKey);
  }

  function testErrAddJobCreditsCreditsOverflowOneStep() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.CreditsDepositOverflow.selector)
    );

    uint256 value = uint256(type(uint88).max) + 5;
    vm.deal(alice, value);
    vm.prank(alice);
    agent.depositJobCredits{ value: value}(jobKey);
  }

  function testErrAddJobCreditsCreditsOverflowTwoSteps() public {
    // 1st
    uint256 first = uint256(type(uint88).max) - 10;
    vm.deal(alice, first);
    vm.prank(alice);
    agent.depositJobCredits{ value: first }(jobKey);

    // 2nd
    uint256 second = 11;
    vm.deal(alice, second);
    vm.prank(alice);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.CreditsDepositOverflow.selector)
    );
    agent.depositJobCredits{ value: second }(jobKey);
  }

  // withdrawJobCredits()

  function testPartialWithdrawJobCredits() public {
    vm.prank(alice);
    agent.depositJobCredits{ value: 1.2 ether}(jobKey);
    uint256 bobBalanceBefore = bob.balance;

    // 1st withdrawal
    vm.expectEmit(true, true, true, true, address(agent));
    emit WithdrawJobCredits(jobKey, alice, bob, 0.8 ether);

    vm.prank(alice);
    agent.withdrawJobCredits(jobKey, bob, 0.8 ether);

    PPAgentV2.Job memory job = agent.getJob(jobKey);
    assertEq(job.credits, 0.4 ether);

    assertEq(bob.balance, bobBalanceBefore + 0.8 ether);

    // 2nd withdrawal
    vm.prank(alice);
    agent.withdrawJobCredits(jobKey, bob, 0.4 ether);

    job = agent.getJob(jobKey);
    assertEq(job.credits, 0 ether);

    assertEq(bob.balance, bobBalanceBefore + 1.2 ether);
  }

  function testErrWithdrawJobCreditsMissingAmount() public {
    vm.prank(alice);
    agent.depositJobCredits{ value: 1.2 ether}(jobKey);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingAmount.selector)
    );

    vm.prank(alice);
    agent.withdrawJobCredits(jobKey, bob, 0);
  }

  function testErrWithdrawJobCreditsNotTheOwner() public {
    vm.prank(alice);
    agent.depositJobCredits{ value: 1.2 ether}(jobKey);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.OnlyJobOwner.selector)
    );

    vm.prank(bob);
    agent.withdrawJobCredits(jobKey, bob, 1.21 ether);
  }

  function testErrWithdrawJobCreditsUnderflow() public {
    vm.prank(alice);
    agent.depositJobCredits{ value: 1.2 ether}(jobKey);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.CreditsWithdrawalUnderflow.selector)
    );

    vm.prank(alice);
    agent.withdrawJobCredits(jobKey, bob, 1.21 ether);
  }

  function testErrWithdrawJobCreditsRevert() public {
    vm.prank(alice);
    agent.depositJobCredits{ value: 1.2 ether}(jobKey);

    vm.expectRevert(bytes("SOME_REASON"));

    vm.prank(alice);
    agent.withdrawJobCredits(jobKey, payable(this), 1.2 ether);
  }

  // transferJob()

  function testJobTransfer() public {
    assertEq(agent.jobOwners(jobKey), alice);

    vm.expectEmit(true, true, true, true, address(agent));
    emit JobTransfer(jobKey, alice, bob);
    vm.prank(alice);
    agent.transferJob(jobKey, bob);

    assertEq(agent.jobOwners(jobKey), bob);
  }

  function testErrJobTransferNotTheOwner() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.OnlyJobOwner.selector)
    );

    vm.prank(bob);
    agent.transferJob(jobKey, bob);
  }

  // testSetJobConfig()

  function testSetJobConfig() public {
    uint256 job = agent.getJobRaw(jobKey);
    assertEq(bytes32(job), 0x0000000000000f000000000a0023006400000000000000000000000000000101);
    assertEq(lens.isJobActivePure(job), true);

    (bool active, bool ownerFunds, bool assertSelector,) = lens.parseConfigPure(job);
    assertEq(active, true);
    assertEq(ownerFunds, false);
    assertEq(assertSelector, false);

    // change #1
    vm.expectEmit(true, true, false, true, address(agent));
    emit SetJobConfig(jobKey, false, true, true);
    vm.prank(alice);
    agent.setJobConfig(jobKey, false, true, true);

    job = agent.getJobRaw(jobKey);
    assertEq(lens.isJobActivePure(job), false);
    (active, ownerFunds, assertSelector,) = lens.parseConfigPure(job);
    assertEq(active, false);
    assertEq(ownerFunds, true);
    assertEq(assertSelector, true);

    assertEq(bytes32(job), 0x0000000000000f000000000a0023006400000000000000000000000000000106);

    // change #2
    vm.expectEmit(true, true, false, true, address(agent));
    emit SetJobConfig(jobKey, true, true, true);

    vm.prank(alice);
    agent.setJobConfig(jobKey, true, true, true);

    job = agent.getJobRaw(jobKey);
    assertEq(lens.isJobActivePure(job), true);
    (active, ownerFunds, assertSelector,) = lens.parseConfigPure(job);
    assertEq(active, true);
    assertEq(ownerFunds, true);
    assertEq(assertSelector, true);
    assertEq(bytes32(job), 0x0000000000000f000000000a0023006400000000000000000000000000000107);
  }

  function testErrSetJobActiveNotOwner() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.OnlyJobOwner.selector)
    );

    vm.prank(bob);
    agent.setJobConfig(jobKey, false, true, false);
  }

  // updateJob()

  function testUpdateJob() public {
    PPAgentV2.Job memory job = agent.getJob(jobKey);
    assertEq(job.maxBaseFeeGwei, 100);
    assertEq(job.rewardPct, 35);
    assertEq(job.fixedReward, 10);
    assertEq(job.intervalSeconds, 15);
    assertEq(job.calldataSource, CALLDATA_SOURCE_SELECTOR);

    vm.expectEmit(true, false, false, true, address(agent));
    emit JobUpdate(jobKey, 200, 55, 20, 30, 60);

    vm.prank(alice);
    agent.updateJob({
      jobKey_: jobKey,
      maxBaseFeeGwei_: 200,
      rewardPct_: 55,
      fixedReward_: 20,
      jobMinCvp_: 30,
      intervalSeconds_: 60
    });

    job = agent.getJob(jobKey);
    assertEq(job.maxBaseFeeGwei, 200);
    assertEq(job.rewardPct, 55);
    assertEq(job.fixedReward, 20);
    assertEq(job.intervalSeconds, 60);
    assertEq(agent.jobMinKeeperCvp(jobKey), 30);
  }

  function testUpdateJobToggleMinKeeperCvpFlag() public {
    PPAgentV2.Job memory job = agent.getJob(jobKey);
    (bool active,,,bool checkKeeperMinCvpDeposit) = lens.parseConfigPure(job.config);
    assertEq(active, true);
    assertEq(checkKeeperMinCvpDeposit, false);
    assertEq(agent.jobMinKeeperCvp(jobKey), 0);

    // 1. Toggle to true
    vm.prank(alice);
    agent.updateJob(jobKey, 200, 55, 20, 10, 60);
    job = agent.getJob(jobKey);
    (,,,checkKeeperMinCvpDeposit) = lens.parseConfigPure(job.config);
    assertEq(active, true);
    assertEq(checkKeeperMinCvpDeposit, true);
    assertEq(agent.jobMinKeeperCvp(jobKey), 10);

    // 2. Set another positive value
    vm.prank(alice);
    agent.updateJob(jobKey, 200, 55, 20, 20, 60);
    job = agent.getJob(jobKey);
    (,,,checkKeeperMinCvpDeposit) = lens.parseConfigPure(job.config);
    assertEq(active, true);
    assertEq(checkKeeperMinCvpDeposit, true);
    assertEq(agent.jobMinKeeperCvp(jobKey), 20);

    // 3. Toggle to negative
    vm.prank(alice);
    agent.updateJob(jobKey, 200, 55, 20, 0, 60);
    job = agent.getJob(jobKey);
    (,,,checkKeeperMinCvpDeposit) = lens.parseConfigPure(job.config);
    assertEq(active, true);
    assertEq(checkKeeperMinCvpDeposit, false);
    assertEq(agent.jobMinKeeperCvp(jobKey), 0);

    // 4. Still negative
    vm.prank(alice);
    agent.updateJob(jobKey, 200, 55, 20, 0, 60);
    job = agent.getJob(jobKey);
    (,,,checkKeeperMinCvpDeposit) = lens.parseConfigPure(job.config);
    assertEq(active, true);
    assertEq(checkKeeperMinCvpDeposit, false);
    assertEq(agent.jobMinKeeperCvp(jobKey), 0);
  }

  function testErrUpdateJobNotOwner() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.OnlyJobOwner.selector)
    );

    vm.prank(bob);
    agent.updateJob(jobKey, 200, 55, 20, 0, 60);
  }

  function testErrUpdateJobMissingMaxBaseFeeGwei() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingMaxBaseFeeGwei.selector)
    );

    vm.prank(alice);
    agent.updateJob(jobKey, 0, 55, 20, 0, 60);
  }

  function testErrUpdateJobMoFixedNorPremiumPctReward() public {
    vm.prank(alice);
    agent.updateJob(jobKey, 200, 5, 0, 0, 60);
    vm.prank(alice);
    agent.updateJob(jobKey, 200, 0, 5, 0, 60);

    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.NoFixedNorPremiumPctReward.selector)
    );

    vm.prank(alice);
    agent.updateJob(jobKey, 200, 0, 0, 0, 60);
  }

  function testErrUpdateJobWithSelectorShouldHaveInterval() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.JobShouldHaveInterval.selector)
    );

    vm.prank(alice);
    agent.updateJob(jobKey, 200, 55, 20, 0, 0);
  }

  function testErrUpdateJobWithPreDefinedCalldataShouldHaveInterval() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.calldataSource = CALLDATA_SOURCE_PRE_DEFINED;
    (bytes32 myJobKey,) = agent.registerJob(params, resolver1, new bytes(0));
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.JobShouldHaveInterval.selector)
    );

    vm.prank(alice);
    agent.updateJob(myJobKey, 200, 55, 20, 0, 0);
  }

  function testUpdateJobWithResolverCanHaveZeroInterval() public {
    PPAgentV2.RegisterJobParams memory params = params1;
    params.calldataSource = CALLDATA_SOURCE_RESOLVER;
    (bytes32 myJobKey,) = agent.registerJob(params, resolver1, new bytes(0));

    vm.prank(alice);
    agent.updateJob(myJobKey, 200, 55, 20, 0, 0);
  }

  // setJobResolver()

  function testSetJobResolver() public jobWithResolverCalldataSource {
    PPAgentV2.Resolver memory current = agent.getResolver(jobKey);
    assertEq(current.resolverAddress, address(1));
    assertEq(current.resolverCalldata, new bytes(0));

    PPAgentV2.Resolver memory newResolver = PPAgentV2.Resolver(address(2), hex"313373");

    vm.expectEmit(true, true, false, true, address(agent));
    emit SetJobResolver(jobKey, newResolver.resolverAddress, newResolver.resolverCalldata);
    vm.prank(alice);
    agent.setJobResolver(jobKey, newResolver);

    current = agent.getResolver(jobKey);
    assertEq(current.resolverAddress, address(2));
    assertEq(current.resolverCalldata, hex"313373");
  }

  function testErrSetResolverNotOwner() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.OnlyJobOwner.selector)
    );

    PPAgentV2.Resolver memory newResolver = PPAgentV2.Resolver(address(2), hex"313373");
    agent.setJobResolver(jobKey, newResolver);
  }

  function testErrSetResolverOnlyResolverCalldataSource() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.NotSupportedByJobCalldataSource.selector)
    );

    PPAgentV2.Resolver memory newResolver = PPAgentV2.Resolver(address(2), hex"313373");
    vm.prank(alice);
    agent.setJobResolver(jobKey, newResolver);
  }

  function testErrSetResolverMissingResolverAddress() public jobWithResolverCalldataSource {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.MissingResolverAddress.selector)
    );

    PPAgentV2.Resolver memory newResolver = PPAgentV2.Resolver(address(0), hex"313373");
    vm.prank(alice);
    agent.setJobResolver(jobKey, newResolver);
  }

  // setPreDefinedCalldata()

  function testSetPreDefinedCalldata() public jobWithPreDefinedCalldataSource {
    assertEq(agent.preDefinedCalldatas(jobKey), new bytes(0));

    vm.expectEmit(true, true, false, true, address(agent));
    emit SetJobPreDefinedCalldata(jobKey, hex"313373");
    vm.prank(alice);
    agent.setJobPreDefinedCalldata(jobKey, hex"313373");

    assertEq(agent.preDefinedCalldatas(jobKey), hex"313373");
  }

  function testErrSetPreDefinedCalldataNotOwner() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.OnlyJobOwner.selector)
    );

    agent.setJobPreDefinedCalldata(jobKey, hex"313373");
  }

  function testErrSetPreDefinedCalldataForSelectorJob() public {
    vm.expectRevert(
      abi.encodeWithSelector(PPAgentV2.NotSupportedByJobCalldataSource.selector)
    );

    vm.prank(alice);
    agent.setJobPreDefinedCalldata(jobKey, hex"313373");
  }

  // useJobOwnerCredits

  function testSetUseJobOwnerCredits() public {
    (,bool useOwnerCredits,,) = lens.parseConfigPure(agent.getJobRaw(jobKey));
    assertEq(useOwnerCredits, false);

    vm.prank(alice);
    agent.setJobConfig(jobKey, true, true, false);

    (,useOwnerCredits,,) = lens.parseConfigPure(agent.getJobRaw(jobKey));
    assertEq(useOwnerCredits, true);

    vm.prank(alice);
    agent.setJobConfig(jobKey, true, false, false);

    (,useOwnerCredits,,) = lens.parseConfigPure(agent.getJobRaw(jobKey));
    assertEq(useOwnerCredits, false);
  }

  receive() external payable {
    revert("SOME_REASON");
  }
}
