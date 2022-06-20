// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockCVP is ERC20 {
  constructor() ERC20("Buzz Token 1", "BZZ1") {
    _mint(msg.sender, 2_000_000_000_000 * 10 ** decimals());
  }
}
