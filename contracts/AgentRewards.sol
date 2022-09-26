// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPPAgentV2Viewer } from "../contracts/PPAgentV2.sol";

contract AgentRewards is Ownable, Pausable {
  event SetSinglePayoutStakePpm(uint256 singlePayoutStakePpm);
  event SetWhitelist(uint256 indexed keeperId, bool allowance);
  event Claim(uint256 indexed keeperId, address indexed to, uint256 amount);

  uint256 public immutable PERIOD_LENGTH_SECONDS;
  IERC20 public immutable CVP;
  IPPAgentV2Viewer public immutable AGENT;
  address public immutable TREASURY;

  uint256 public singlePayoutStakePpm;

  mapping(uint256 => bool) public whitelist;
  // keeperId => timestamp
  mapping(uint256 => uint256) public lastClaimedAt;

  constructor(address owner_, address cvp_, address agent_, address treasury_, uint256 periodLengthSeconds_, uint256 singlePayoutStakePpm_) {
    CVP = IERC20(cvp_);
    AGENT = IPPAgentV2Viewer(agent_);
    PERIOD_LENGTH_SECONDS = periodLengthSeconds_;
    TREASURY = treasury_;
    singlePayoutStakePpm = singlePayoutStakePpm_;
    _transferOwnership(owner_);
  }

  /*** OWNER INTERFACE ***/

  function setSinglePayoutStakePpm(uint256 _singlePayoutStakePpm) external onlyOwner {
    singlePayoutStakePpm = _singlePayoutStakePpm;
    emit SetSinglePayoutStakePpm(_singlePayoutStakePpm);
  }

  function setWhitelist(uint256[] memory keepers, bool[] memory allowances) external onlyOwner {
    uint256 len = keepers.length;
    require(len == allowances.length, "Length mismatch");

    for (uint256 i = 0; i < len; i++) {
      whitelist[keepers[i]] = allowances[i];
      emit SetWhitelist(keepers[i], allowances[i]);
    }
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }

  /*** KEEPER INTERFACE ***/

  function claim(uint256 keeperId_, address to_) external whenNotPaused {
    (address worker, uint256 currentStake) = AGENT.getKeeperWorkerAndStake(keeperId_);
    require(worker == msg.sender, "Only keeper worker allowed");
    require(whitelist[keeperId_], "Keeper should be whitelisted");
    require(cooldownPassed(keeperId_), "Interval");

    uint256 reward = currentStake * singlePayoutStakePpm / 1e6; /* 100% in ppm*/
    require(reward > 0, "Insufficient reward");

    lastClaimedAt[keeperId_] = block.timestamp;
    CVP.transferFrom(TREASURY, to_, reward);

    emit Claim(keeperId_, to_, reward);
  }

  function cooldownPassed(uint256 keeperId_) public view returns (bool) {
    return lastClaimedAt[keeperId_] + PERIOD_LENGTH_SECONDS < block.timestamp;
  }
}
