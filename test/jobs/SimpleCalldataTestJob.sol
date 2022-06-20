// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../contracts/jobs/traits/AgentJob.sol";
import "./ICounter.sol";

contract SimpleCalldataTestJob is ICounter, AgentJob {
  event Increment(address pokedBy, uint256 newCurrent);

  uint256 public current;

  constructor(address agent_) AgentJob (agent_) {
  }

  function myResolver(string calldata pass) external pure returns (bool, bytes memory) {
    require(keccak256(abi.encodePacked(pass)) == keccak256(abi.encodePacked("myPass")), "invalid pass");

    return (true, abi.encodeWithSelector(
      SimpleCalldataTestJob.increment.selector,
      5, true, uint24(42), "d-value"
    ));
  }

  function increment(uint256 a, bool b, uint24 c, string calldata d) external onlyAgent {
    require(a == 5, "invalid a");
    require(b == true, "invalid b");
    require(c == uint24(42), "invalid c");
    require(keccak256(abi.encodePacked(d)) == keccak256(abi.encodePacked("d-value")), "invalid d");
    current += 1;
    emit Increment(msg.sender, current);
  }

  function increment2() external pure {
    revert("unexpected increment2");
  }
}
