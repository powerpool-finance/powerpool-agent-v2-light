// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

abstract contract MultiAgentJob {
  mapping(address => bool) public canAccess;

  modifier onlyAgent() {
    require(canAccess[msg.sender] == true);
    _;
  }

  constructor(address[] memory agents) {
    for (uint256 i = 0; i < agents.length; i++) {
      canAccess[agents[i]] = true;
    }
  }
}
