// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../contracts/jobs/traits/AgentJob.sol";
import "./ICounter.sol";

contract SimpleCalldataIntervalTestJob is ICounter, AgentJob {
  event Increment(address pokedBy, uint256 newCurrent);

  uint256 public immutable INTERVAL;

  uint256 public current;
  uint256 public lastChangeAt;

  constructor(address agent_, uint256 interval_) AgentJob (agent_) {
    INTERVAL = interval_;
  }

  function myResolver(string calldata pass) external view override returns (bool, bytes memory) {
    require(keccak256(abi.encodePacked(pass)) == keccak256(abi.encodePacked("myPass")), "invalid pass");

    return (
      block.timestamp >= (lastChangeAt + INTERVAL),
      abi.encodeWithSelector(SimpleCalldataIntervalTestJob.increment.selector, 5, true, uint24(42), "d-value")
    );
  }

  function increment(uint256 a, bool b, uint24 c, string calldata d) external onlyAgent {
    require(block.timestamp >= (lastChangeAt + INTERVAL), "interval");

    require(a == 5, "invalid a");
    require(b == true, "invalid b");
    require(c == uint24(42), "invalid c");
    require(keccak256(abi.encodePacked(d)) == keccak256(abi.encodePacked("d-value")), "invalid d");
    current += 1;
    lastChangeAt = block.timestamp;
    emit Increment(msg.sender, current);
  }
}
