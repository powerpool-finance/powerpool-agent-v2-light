// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../contracts/jobs/traits/AgentJob.sol";
import "./ICounter.sol";

contract NoCalldataTestJob is ICounter, AgentJob {
  event Increment(address pokedBy, uint256 newCurrent);

  uint256 public current;

  constructor(address agent_) AgentJob (agent_) {
  }

  function myResolver(string calldata pass) external pure returns (bool ok, bytes memory cd) {
    require(keccak256(abi.encodePacked(pass)) == keccak256(abi.encodePacked("myPass")), "invalid pass");

    return (true, new bytes(0));
  }

  fallback() external onlyAgent {
    current += 1;
    emit Increment(msg.sender, current);
  }
}
