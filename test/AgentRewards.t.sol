// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./TestHelper.sol";
import "../contracts/PPAgentV2.sol";
import "../contracts/AgentRewards.sol";

contract AgentRewardsTest is TestHelper {
  event SetSinglePayoutStakePpm(uint256 singlePayoutStakePpm);
  event SetWhitelist(uint256 indexed keeperId, bool allowance);
  event Claim(uint256 indexed keeperId, address indexed to, uint256 amount);

  AgentRewards internal agentRewards;
  uint256 internal kid1;
  uint256 internal kid2;

  constructor() {
    cvp = new MockCVP();
    agent = new PPAgentV2(owner, address(cvp), MIN_DEPOSIT_3000_CVP, 3 days);
  }

  function setUp() public override {
    agentRewards = new AgentRewards({
      owner_: owner,
      cvp_: address(cvp),
      agent_: address(agent),
      treasury_: charlie,
      periodLengthSeconds_: 3 days,
      singlePayoutStakePpm_: 2_000 /* 0.02% */
    });

    {
      cvp.transfer(keeperAdmin, 15_000 ether);
      vm.prank(keeperAdmin);
      cvp.approve(address(agent), 15_000 ether);
      vm.prank(keeperAdmin);
      kid1 = agent.registerAsKeeper(keeperWorker, 5_000 ether);
      vm.prank(keeperAdmin);
      kid2 = agent.registerAsKeeper(alice, 10_000 ether);
    }
    cvp.transfer(charlie, 100_000 ether);
    vm.prank(charlie);
    cvp.approve(address(agentRewards), 100_000 ether);
  }

  function testGetters() public {
    assertEq(address(agentRewards.CVP()), address(agent.CVP()));
    assertEq(address(agentRewards.AGENT()), address(agent));
    assertEq(agentRewards.TREASURY(), charlie);
    assertEq(agentRewards.PERIOD_LENGTH_SECONDS(), 3 days);
    assertEq(agentRewards.singlePayoutStakePpm(), 2_000);

    // Ownable
    assertEq(agentRewards.owner(), owner);
  }

  // setSinglePayoutStakePpm()

  function testOwnerCanUpdateSinglePayoutStakePpm() public {
    assertEq(agentRewards.singlePayoutStakePpm(), 2_000);
    vm.prank(owner);
    vm.expectEmit(true, true, false, true, address(agentRewards));
    emit SetSinglePayoutStakePpm(1_000_000);
    agentRewards.setSinglePayoutStakePpm(1_000_000);
    assertEq(agentRewards.singlePayoutStakePpm(), 1_000_000);

    vm.prank(owner);
    agentRewards.setSinglePayoutStakePpm(0);
    assertEq(agentRewards.singlePayoutStakePpm(), 0);
  }

  function testErrNonOwnerCanUpdateSinglePayoutStakePpm() public {
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    agentRewards.setSinglePayoutStakePpm(1_000_000);
  }

  // setWhitelist()

  function testWhitelist() public {
    uint256[] memory keepers = new uint256[](2);
    bool[] memory allowances = new bool[](2);

    assertEq(agentRewards.whitelist(kid1), false);
    assertEq(agentRewards.whitelist(kid2), false);

    // set
    keepers[0] = kid1;
    keepers[1] = kid2;
    allowances[0] = true;
    allowances[1] = true;

    vm.prank(owner);
    vm.expectEmit(true, true, false, true, address(agentRewards));
    emit SetWhitelist(kid1, true);
    vm.expectEmit(true, true, false, true, address(agentRewards));
    emit SetWhitelist(kid2, true);
    agentRewards.setWhitelist(keepers, allowances);

    assertEq(agentRewards.whitelist(kid1), true);
    assertEq(agentRewards.whitelist(kid2), true);

    // unset
    keepers[0] = kid1;
    keepers[1] = kid2;
    allowances[0] = false;
    allowances[1] = false;

    vm.prank(owner);
    agentRewards.setWhitelist(keepers, allowances);

    assertEq(agentRewards.whitelist(kid1), false);
    assertEq(agentRewards.whitelist(kid2), false);
  }

  function testErrNonOwnerSetWhitelist() public {
    uint256[] memory keepers = new uint256[](2);
    bool[] memory allowances = new bool[](2);
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    agentRewards.setWhitelist(keepers, allowances);
  }

  function testErrSetWhitelistDiffLengths() public {
    uint256[] memory keepers = new uint256[](1);
    bool[] memory allowances = new bool[](2);
    vm.expectRevert(bytes("Length mismatch"));
    vm.prank(owner);
    agentRewards.setWhitelist(keepers, allowances);
  }

  // pause() / unpause()

  function testPauseUnpause() public {
    assertEq(agentRewards.paused(), false);
    vm.prank(owner);
    agentRewards.pause();
    assertEq(agentRewards.paused(), true);
    vm.prank(owner);
    agentRewards.unpause();
    assertEq(agentRewards.paused(), false);
  }

  function testErrPauseNonOwner() public {
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    agentRewards.pause();
  }

  function testErrUnpauseNonOwner() public {
    vm.expectRevert(bytes("Ownable: caller is not the owner"));
    agentRewards.unpause();
  }

  // claim()

  function _whitelist(uint256 keeperId_) internal {
    uint256[] memory keepers = new uint256[](1);
    bool[] memory allowances = new bool[](1);
    keepers[0] = keeperId_;
    allowances[0] = true;

    vm.prank(owner);
    agentRewards.setWhitelist(keepers, allowances);
  }

  function testClaim() public {
    _whitelist(kid1);

    assertEq(agentRewards.lastClaimedAt(kid1), 0);

    uint256 bobBalanceBefore = cvp.balanceOf(bob);
    vm.prank(keeperWorker, keeperWorker);
    vm.expectEmit(true, true, false, true, address(agentRewards));
    emit Claim(kid1, bob, 10 ether);
    agentRewards.claim(kid1, bob);
    assertEq(agentRewards.lastClaimedAt(kid1), 1600000000);

    // 5_000 * 0.2% = 10
    assertEq(cvp.balanceOf(bob) - bobBalanceBefore, 10 ether);
    assertEq(block.timestamp, 1600000000);

    vm.expectRevert(bytes("Interval"));
    vm.prank(keeperWorker);
    agentRewards.claim(kid1, bob);

    vm.warp(block.timestamp + 2 days + 23 hours);
    assertEq(block.timestamp, 1600000000 + 2 days + 23 hours);
    vm.expectRevert(bytes("Interval"));
    vm.prank(keeperWorker);
    agentRewards.claim(kid1, bob);

    // invalid calculation?
    vm.warp(block.timestamp + 1 hours + 1);
    assertEq(block.timestamp, 1600000000 + 3 days + 1);
    bobBalanceBefore = cvp.balanceOf(bob);
    vm.prank(keeperWorker);
    agentRewards.claim(kid1, bob);
    assertEq(agentRewards.lastClaimedAt(kid1), 1600000000 + 3 days + 1);
    assertEq(cvp.balanceOf(bob) - bobBalanceBefore, 10 ether);
  }

  function testErrClaimNotWorker() public {
    vm.expectRevert(bytes("Only keeper worker allowed"));
    vm.prank(keeperAdmin, keeperAdmin);
    agentRewards.claim(kid1, bob);
  }

  function testErrClaimNotWhitelisted() public {
    vm.expectRevert(bytes("Keeper should be whitelisted"));
    vm.prank(keeperWorker, keeperWorker);
    agentRewards.claim(kid1, bob);
  }

  function testErrClaimNotEOA() public {
    vm.expectRevert(bytes("EOA only"));
    vm.prank(keeperWorker);
    agentRewards.claim(kid1, bob);
  }
}
