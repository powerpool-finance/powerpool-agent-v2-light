// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../contracts/jobs/traits/AgentJob.sol";
import "./ICounter.sol";

contract ComplexCalldataTestJob is ICounter, AgentJob {
  event Increment(address pokedBy, uint256 newCurrent);

  uint256 public current;

  constructor(address agent_) AgentJob (agent_) {
  }

  function myResolver(string calldata pass) external pure returns (bool, bytes memory) {
    require(keccak256(abi.encodePacked(pass)) == keccak256(abi.encodePacked("myPass")), "invalid pass");

    string[] memory b = new string[](2);
    b[0] = "b-value-0";
    b[1] = "b-value-1";

    ComplexCalldataTestJob.Params memory c;
    c.v1.l21 = new bool[](3);
    c.v1.l21[0] = true;
    c.v1.l21[1] = false;
    c.v1.l21[2] = true;

    c.v2[0] = new bool[][](3);
    c.v2[0][0] = new bool[](5);
    c.v2[0][1] = new bool[](6);
    c.v2[0][2] = new bool[](7);

    c.v2[0][2][5] = true;

    c.v2[1] = new bool[][](4);

    return (true, abi.encodeWithSelector(
        ComplexCalldataTestJob.increment.selector,
        uint24(42), b, c
    ));
  }

  struct L2 {
    bool[] l21;
  }

  struct Params {
    L2 v1;
    bool[][][2] v2;
  }

  function increment(uint24 a, string[] calldata b, Params calldata c) external onlyAgent {
    require(a == uint24(42), "invalid a");
    require(b.length == 2, "invalid b length");
    require(keccak256(abi.encodePacked(b[0])) == keccak256(abi.encodePacked("b-value-0")), "invalid b-0");
    require(keccak256(abi.encodePacked(b[1])) == keccak256(abi.encodePacked("b-value-1")), "invalid b-1");

    require(c.v1.l21.length == 3, "invalid c.v1.l21 length");
    require(c.v1.l21[0] == true, "invalid c.v1.l21.0 value");
    require(c.v1.l21[1] == false, "invalid c.v1.l21.1 value");
    require(c.v1.l21[2] == true, "invalid c.v1.l21.2 value");

    require(c.v2.length == 2, "invalid c.v2 length");
    require(c.v2[0].length == 3, "invalid c.v2.0 length");
    require(c.v2[0][0].length == 5, "invalid c.v2.0.0 length");
    require(c.v2[0][1].length == 6, "invalid c.v2.0.1 length");
    require(c.v2[0][2].length == 7, "invalid c.v2.0.2 length");
    require(c.v2[0][2][5] == true, "invalid c.v2.0.2.5 value");
    require(c.v2[0][2][6] == false, "invalid c.v2.0.2.6 value");

    require(c.v2[1].length == 4, "invalid c.v2.1 length");
    require(c.v2[1][0].length == 0, "invalid c.v2.1.0 length");
    require(c.v2[1][1].length == 0, "invalid c.v2.1.1 length");
    require(c.v2[1][2].length == 0, "invalid c.v2.1.2 length");
    require(c.v2[1][3].length == 0, "invalid c.v2.1.3 length");

    current += 1;
    emit Increment(msg.sender, current);
  }

  function increment2() external pure {
    revert("unexpected increment2");
  }
}
