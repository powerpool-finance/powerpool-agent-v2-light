// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../contracts/jobs/traits/AgentJob.sol";
import "../../contracts/PPAgentV2.sol";
import "./ICounter.sol";

contract JobTopupTestJob is AgentJob {
  constructor(address agent_) AgentJob (agent_) {
  }

  function myResolver(bytes32 jobKey_) external pure returns (bool, bytes memory) {
    return (true, abi.encodeWithSelector(JobTopupTestJob.execute.selector, jobKey_));
  }

  function execute(bytes32 jobKey_) external onlyAgent {
    require(address(this).balance >= 8.42 ether, "missing 8.42 ether");
    PPAgentV2(agent).depositJobCredits{value: 8.42 ether}(jobKey_);
  }

  receive() external payable {
  }
}
