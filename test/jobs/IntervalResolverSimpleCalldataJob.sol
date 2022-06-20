// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../contracts/jobs/traits/AgentJob.sol";

contract IntervalResolverSimpleCalldataJob is AgentJob {
  event Increment(address pokedBy, uint256 newCurrent);

  uint256 public constant INTERVAL = 30;

  uint256 public lastChangeAt;
  uint256 public current;

  constructor(address agent_) AgentJob (agent_) {
  }

  function myResolver() external view returns (bool ok, bytes memory cd) {
    if (block.timestamp >= (lastChangeAt + INTERVAL)) {
      return (
        true,
        abi.encodeWithSelector(
          IntervalResolverSimpleCalldataJob.increment.selector,
          msg.sender,
          true
        )
      );
    } else {
      return (false, new bytes(0));
    }
  }

  function increment(address sender, bool ok) external onlyAgent {
    require(block.timestamp >= (lastChangeAt + INTERVAL), "interval");
    require(sender == tx.origin, "not tx.origin");
    require(ok, "not ok");

    current += 1;

    lastChangeAt = block.timestamp;
    emit Increment(msg.sender, current);
  }
}
