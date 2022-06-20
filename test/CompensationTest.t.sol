// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/forge-std/src/Test.sol";
import "../contracts/PPAgentV2.sol";
import "../contracts/PPAgentV2Flags.sol";
import "./mocks/MockCVP.sol";

contract CompensationTest is Test, PPAgentV2Flags {
  address internal alice = address(0xaAaAaAaaAaAaAaaAaAAAAAAAAaaaAaAaAaaAaaAa);
  address internal bob = address(0xbBbBBBBbbBBBbbbBbbBbbbbBBbBbbbbBbBbbBBbB);
  address internal keeper = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
  uint256 internal constant CVP_LIMIT = 100_000_000 ether;

  MockCVP internal cvp;
  PPAgentV2 internal agent;

  function setUp() public {
    cvp = new MockCVP();
    agent = new PPAgentV2(bob, address(cvp), 3_000 ether, 3 days);
  }

  function testGasCompensationPctLt100AndFixed() public {
    assertEq(
      agent.calculateCompensationPure({
        rewardPct_: 35,
        fixedReward_: 22,
        blockBaseFee_: 45 gwei,
        gasUsed_: 150_000
      }),
      180_000 * 45 gwei * 35 / 100 + 0.022 ether
    );
  }

  function testGasCompensationPctGt100AndFixed() public {
    assertEq(
      agent.calculateCompensationPure({
        rewardPct_: 135,
        fixedReward_: 22,
        blockBaseFee_: 45 gwei,
        gasUsed_: 150_000
      }),
      180_000 * 45 gwei * 135 / 100 + 0.022 ether
    );
  }

  function testGasCompensationPctOnly() public {
    assertEq(
      agent.calculateCompensationPure({
        rewardPct_: 35,
        fixedReward_: 0,
        blockBaseFee_: 45 gwei,
        gasUsed_: 150_000
      }),
      180_000 * 45 gwei * 35 / 100
    );
  }

  function testGasCompensationFixedOnly() public {
    assertEq(
      agent.calculateCompensationPure({
        rewardPct_: 0,
        fixedReward_: 22,
        blockBaseFee_: 45 gwei,
        gasUsed_: 150_000
      }),
      0.022 ether
    );
  }
}
