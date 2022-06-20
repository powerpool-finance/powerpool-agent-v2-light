// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./traits/MultiAgentJob.sol";

contract CounterJob is MultiAgentJob {
  event Increment(address pokedBy, uint256 newCurrent);

  uint256 public current;

  constructor(address[] memory agents_) MultiAgentJob (agents_) {
  }

  function increment() external onlyAgent {
    current += 1;
    emit Increment(msg.sender, current);
  }
}
