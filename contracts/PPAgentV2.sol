// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "./PPAgentV2Flags.sol";

library ConfigFlags {
  function check(uint256 cfg, uint256 flag) internal pure returns (bool) {
    return (cfg & flag) != 0;
  }
}

interface IPPAgentV2 {
  function execute_44g58pv() external;
}

/**
 * @title PowerAgentLite
 * @author PowerPool
 */
contract PPAgentV2 is IPPAgentV2, PPAgentV2Flags, Ownable, ERC20, ERC20Permit  {
  error OnlyOwner();
  error NonEOASender();
  error InsufficientKeeperStake();
  error InsufficientJobScopedKeeperStake();
  error KeeperWorkerNotAuthorized();
  error InsufficientJobCredits(uint256 actual, uint256 wanted);
  error InsufficientJobOwnerCredits(uint256 actual, uint256 wanted);
  error InactiveJob(bytes32 jobKey);
  error JobIdOverflow();
  error OnlyJobOwner();
  error JobWithoutOwner();
  error MissingJobAddress();
  error MissingMaxBaseFeeGwei();
  error NoFixedNorPremiumPctReward();
  error CreditsDepositOverflow();
  error CreditsWithdrawalUnderflow();
  error MissingDeposit();
  error IntervalNotReached(uint256 lastExecutedAt, uint256 interval, uint256 _now);
  error BaseFeeGtGasPrice(uint256 baseFee, uint256 jobMaxBaseFeeGwei);
  error InvalidCalldataSource();
  error MissingInputCalldata();
  error SelectorCheckFailed();
  error JobCallRevertedWithoutDetails();
  error InsufficientAmountToCoverSlashedStake(uint256 wanted, uint256 actual);
  error AmountGtStake(uint256 wanted, uint256 actualStake, uint256 actualSlashedStake);
  error WithdrawalTimoutNotReached();
  error NoPendingWithdrawal();
  error MissingAmount();
  error WithdrawAmountExceedsAvailable(uint256 wanted, uint256 actual);
  error JobShouldHaveInterval();
  error InvalidJobAddress();
  error MissingResolverAddress();
  error NotSupportedByJobCalldataSource();
  error OnlyKeeperAdmin();
  error TimeoutTooBig();
  error FeeTooBig();
  error InsufficientAmount();
  error OnlyPendingOwner();

  string public constant VERSION = "2.0.0";
  uint256 internal constant MAX_PENDING_WITHDRAWAL_TIMEOUT_SECONDS = 30 days;
  uint256 internal constant MAX_FEE_PPM = 5e4;
  uint256 internal constant FIXED_PAYMENT_MULTIPLIER = 1e15;
  uint256 internal constant JOB_RUN_GAS_OVERHEAD = 40_000;

  enum CalldataSourceType {
    SELECTOR,
    PRE_DEFINED,
    RESOLVER
  }

  IERC20 public immutable CVP;

  event Execute(
    bytes32 indexed jobKey,
    address indexed job,
    uint256 keeperId,
    uint256 gasUsed,
    uint256 baseFee,
    uint256 gasPrice,
    uint256 compensation,
    bytes32 binJobAfter
  );
  event WithdrawFees(address indexed to, uint256 amount);
  event Slash(uint256 indexed keeperId, address indexed to, uint256 currentAmount, uint256 pendingAmount);
  event RegisterAsKeeper(uint256 indexed keeperId, address indexed keeperAdmin, address indexed keeperWorker);
  event SetWorkerAddress(uint256 indexed keeperId, address indexed worker);
  event Stake(uint256 indexed keeperId, uint256 amount, address staker, address receiver);
  event InitiateRedeem(uint256 indexed keeperId, uint256 redeemAmount, uint256 stakeAmount, uint256 slashedStakeAmount);
  event FinalizeRedeem(uint256 indexed keeperId, address indexed beneficiary, uint256 amount);
  event WithdrawCompensation(uint256 indexed keeperId, address indexed to, uint256 amount);
  event DepositJobCredits(bytes32 indexed jobKey, address indexed depositor, uint256 amount, uint256 fee);
  event WithdrawJobCredits(bytes32 indexed jobKey, address indexed owner, address indexed to, uint256 amount);
  event DepositJobOwnerCredits(address indexed jobOwner, address indexed depositor, uint256 amount, uint256 fee);
  event WithdrawJobOwnerCredits(address indexed jobOwner, address indexed to, uint256 amount);
  event InitiateJobTransfer(bytes32 indexed jobKey, address indexed from, address indexed to);
  event AcceptJobTransfer(bytes32 indexed jobKey_, address indexed to_);
  event SetJobConfig(bytes32 indexed jobKey, bool isActive_, bool useJobOwnerCredits_, bool assertResolverSelector_);
  event SetJobResolver(bytes32 indexed jobKey, address resolverAddress, bytes resolverCalldata);
  event SetJobPreDefinedCalldata(bytes32 indexed jobKey, bytes preDefinedCalldata);
  event SetAgentParams(uint256 minKeeperCvp_, uint256 timeoutSeconds_, uint256 feePct_);
  event RegisterJob(
    bytes32 indexed jobKey,
    address indexed jobAddress,
    bytes4 indexed jobSelector,
    bool useJobOwnerCredits,
    address owner,
    uint256 jobMinCvp,
    uint256 maxBaseFeeGwei,
    uint256 rewardPct,
    uint256 fixedReward,
    uint256 calldataSource
  );
  event JobUpdate(
    bytes32 indexed jobKey,
    uint256 maxBaseFeeGwei,
    uint256 rewardPct,
    uint256 fixedReward,
    uint256 jobMinCvp,
    uint256 intervalSeconds
  );

  struct Job {
    uint8 config;
    bytes4 selector;
    uint88 credits;
    uint16 maxBaseFeeGwei;
    uint16 rewardPct;
    uint32 fixedReward;
    uint8 calldataSource;

    // For interval jobs
    uint24 intervalSeconds;
    uint32 lastExecutionAt;
  }

  struct Resolver {
    address resolverAddress;
    bytes resolverCalldata;
  }

  struct Keeper {
    address worker;
    uint96 cvpStake;
  }

  uint256 internal minKeeperCvp;
  uint256 internal pendingWithdrawalTimeoutSeconds;
  uint256 internal feeTotal;
  uint256 internal feePpm;
  uint256 internal nextKeeperId;

  // keccak256(jobAddress, id) => ethBalance
  mapping(bytes32 => Job) internal jobs;
  // keccak256(jobAddress, id) => customCalldata
  mapping(bytes32 => bytes) internal preDefinedCalldatas;
  // keccak256(jobAddress, id) => minKeeperCvpStake
  mapping(bytes32 => uint256) internal jobMinKeeperCvp;
  // keccak256(jobAddress, id) => owner
  mapping(bytes32 => address) internal jobOwners;
  // keccak256(jobAddress, id) => resolver(address,calldata)
  mapping(bytes32 => Resolver) internal resolvers;
  // keccak256(jobAddress, id) => pendingAddress
  mapping(bytes32 => address) internal jobPendingTransfers;

  // jobAddress => nextIdToRegister(actually uint24)
  mapping(address => uint256) public jobNextIds;

  // keeperId => (worker,CVP stake)
  mapping(uint256 => Keeper) internal keepers;
  // keeperId => admin
  mapping(uint256 => address) internal keeperAdmins;
  // keeperId => the slashed CVP amount
  mapping(uint256 => uint256) internal slashedStakeOf;
  // keeperId => native token compensation
  mapping(uint256 => uint256) internal compensations;

  // keeperId => pendingWithdrawalCVP amount
  mapping(uint256 => uint256) internal pendingWithdrawalAmounts;
  // keeperId => pendingWithdrawalEndsAt timestamp
  mapping(uint256 => uint256) internal pendingWithdrawalEndsAt;

  // owner => credits
  mapping(address => uint256) public jobOwnerCredits;

  /*** PSEUDO-MODIFIERS ***/

  function _assertOnlyOwner() internal view {
    if (msg.sender != owner()) {
      revert OnlyOwner();
    }
  }

  function _assertOnlyJobOwner(bytes32 jobKey_) internal view {
    if (msg.sender != jobOwners[jobKey_]) {
      revert OnlyJobOwner();
    }
  }

  function _assertOnlyKeeperAdmin(uint256 keeperId_) internal view {
    if (msg.sender != keeperAdmins[keeperId_]) {
      revert OnlyKeeperAdmin();
    }
  }

  function _assertNonZeroAmount(uint256 amount_) internal pure {
    if (amount_ == 0) {
      revert MissingAmount();
    }
  }

  function _assertNonZeroValue() internal view {
    if (msg.value == 0) {
      revert MissingDeposit();
    }
  }

  function _assertJobCalldataSource(bytes32 jobKey_, CalldataSourceType source_) internal view {
    if (CalldataSourceType(jobs[jobKey_].calldataSource) != source_) {
      revert NotSupportedByJobCalldataSource();
    }
  }

  function _assertJobParams(uint256 maxBaseFeeGwei_, uint256 fixedReward_, uint256 rewardPct_) internal pure {
    if (maxBaseFeeGwei_ == 0) {
      revert MissingMaxBaseFeeGwei();
    }

    if (fixedReward_ == 0 && rewardPct_ == 0) {
      revert NoFixedNorPremiumPctReward();
    }
  }

  function _assertInterval(uint256 interval_, CalldataSourceType calldataSource_) internal pure {
    if (interval_ == 0 &&
      (calldataSource_ == CalldataSourceType.SELECTOR || calldataSource_ == CalldataSourceType.PRE_DEFINED)) {
      revert JobShouldHaveInterval();
    }
  }

  constructor(address owner_, address cvp_, uint256 minKeeperCvp_, uint256 pendingWithdrawalTimeoutSeconds_)
    ERC20("PPAgentV2 Staked CVP", "paCVP")
    ERC20Permit("PPAgentV2 Staked CVP")
  {
    minKeeperCvp = minKeeperCvp_;
    CVP = IERC20(cvp_);
    pendingWithdrawalTimeoutSeconds = pendingWithdrawalTimeoutSeconds_;
    _transferOwnership(owner_);
  }

  /*** UPKEEP INTERFACE ***/

  /**
   * Executes a job.
   * The method arguments a tightly coupled with a custom layout in order to save some gas.
   * The calldata has the following layout :
   *  0x      00000000 1b48315d66ba5267aac8d0ab63c49038b56b1dbc 0000f1 03     00001a    402b2eed11
   *  name    selector jobContractAddress                       jobId  config keeperId  calldata (optional)
   *  size b  bytes4   bytes20                                  uint24 uint8  uint24    any
   *  size u  uint32   uint160                                  bytes3 bytes1 bytes3    any
   *  bits    0-3      4-23                                     24-26  27-27  28-30     31+
   */
  function execute_44g58pv() external {
    uint256 gasStart = gasleft();
    bytes32 jobKey;

    assembly ("memory-safe") {
      // size of (address(bytes20)+id(uint24/bytes3))
      let size := 23

      // keccack256(address+id(uint24)) to memory to generate jobKey
      calldatacopy(0, 4, size)
      jobKey := keccak256(0, size)
    }

    address jobAddress;
    uint256 keeperId;
    uint256 cfg;

    assembly ("memory-safe") {
      // load jobAddress, cfg, and keeperId from calldata to the stack
      jobAddress := shr(96, calldataload(4))
      cfg := shr(248, calldataload(27))
      keeperId := shr(232, calldataload(28))
    }

    // 0. Keeper has sufficient stake
    {
      Keeper memory keeper = keepers[keeperId];
      if (keeper.worker != msg.sender) {
        revert KeeperWorkerNotAuthorized();
      }
      if (keeper.cvpStake < minKeeperCvp) {
        revert InsufficientKeeperStake();
      }
    }

    uint256 binJob = getJobRaw(jobKey);

    // 1. Assert the job is active
    {
      if (!ConfigFlags.check(binJob, CFG_ACTIVE)) {
        revert InactiveJob(jobKey);
      }
    }

    // 2. Assert job-scoped keeper's minimum CVP deposit
    if (ConfigFlags.check(binJob, CFG_CHECK_KEEPER_MIN_CVP_DEPOSIT) && keepers[keeperId].cvpStake < jobMinKeeperCvp[jobKey]) {
      revert InsufficientJobScopedKeeperStake();
    }

    // 3. For interval job ensure the interval has passed
    {
      uint256 intervalSeconds = (binJob << 32) >> 232;

      if (intervalSeconds > 0) {
        uint256 lastExecutionAt = binJob >> 224;
        if (lastExecutionAt > 0) {
          uint256 nextExecutionAt;
          unchecked {
            nextExecutionAt = lastExecutionAt + intervalSeconds;
          }
          if (nextExecutionAt > block.timestamp) {
            revert IntervalNotReached(lastExecutionAt, intervalSeconds, block.timestamp);
          }
        }
      }
    }

    // 4. Ensure gas price fits base fee
    uint256 maxBaseFee;
    {
      unchecked {
        maxBaseFee = ((binJob << 112) >> 240)  * 1 gwei;
      }
      if (block.basefee > maxBaseFee && !ConfigFlags.check(cfg, FLAG_ACCEPT_MAX_BASE_FEE_LIMIT)) {
        revert BaseFeeGtGasPrice(block.basefee, maxBaseFee);
      }
    }

    // 5. Ensure msg.sender is EOA
    if (msg.sender != tx.origin) {
      revert NonEOASender();
    }

    bool ok;
    uint256 jobGas = gasleft() - 50_000;

    // Source: Selector
    CalldataSourceType calldataSource = CalldataSourceType((binJob << 56) >> 248);
    if (calldataSource == CalldataSourceType.SELECTOR) {
      bytes4 selector;
      assembly {
        selector := shl(224, shr(8, binJob))
      }
      (ok,) = jobAddress.call{ gas: jobGas }(abi.encode(selector));
    // Source: Bytes
    } else if (calldataSource == CalldataSourceType.PRE_DEFINED) {
      (ok,) = jobAddress.call{ gas: jobGas }(preDefinedCalldatas[jobKey]);
    // Source: Resolver
    } else if (calldataSource == CalldataSourceType.RESOLVER) {
      assembly ("memory-safe") {
        let cdInCdSize := calldatasize()
        // calldata offset is 31
        let beforeCdSize := 31
        let ptr := mload(0x40)
        if lt(cdInCdSize, beforeCdSize) {
          // revert MissingInputCalldata()
          mstore(ptr, 0x47a0bafb00000000000000000000000000000000000000000000000000000000)
          revert(ptr, 4)
        }
        let cdSize := sub(cdInCdSize, beforeCdSize)
        mstore(0x40, add(ptr, cdSize))
        calldatacopy(ptr, beforeCdSize, cdSize)
        // CFG_ASSERT_RESOLVER_SELECTOR = 0x04 from PPAgentLiteFlags
        if and(binJob, 0x04) {
          if iszero(eq(
            // actual
            shl(224, shr(224, calldataload(31))),
            // expected
            shl(224, shr(8, binJob))
          )) {
            // revert SelectorCheckFailed()
            mstore(ptr, 0x84fb827500000000000000000000000000000000000000000000000000000000)
            revert(ptr, 4)
          }
        }
        // The remaining gas could not be less than 50_000
        ok := call(jobGas, jobAddress, 0, ptr, cdSize, 0x0, 0x0)
      }
    } else {
      // Should never be reached
      revert InvalidCalldataSource();
    }

    // Transaction succeeded
    if (ok) {
      uint256 gasUsed;
      unchecked {
        gasUsed = gasStart - gasleft();
      }

      uint256 compensation;
      {
        uint256 min = block.basefee;
        if (maxBaseFee < min) {
          min = maxBaseFee;
        }

        compensation = _calculateCompensation(binJob, min, gasUsed);
      }
      {
        bool jobChanged;

        if (ConfigFlags.check(binJob, CFG_USE_JOB_OWNER_CREDITS)) {
          // use job owner credits
          _useJobOwnerCredits(jobKey, compensation);
        } else {
          // use job credits
          uint256 creditsBefore = (binJob << 128) >> 168;
          if (creditsBefore < compensation) {
            revert InsufficientJobCredits(creditsBefore, compensation);
          }

          uint256 creditsAfter;
          unchecked {
            creditsAfter = creditsBefore - compensation;
          }
          // update job credits
          binJob = binJob & BM_CLEAR_CREDITS | (creditsAfter << 40);
          jobChanged = true;
        }

        if (ConfigFlags.check(cfg, FLAG_ACCRUE_REWARD)) {
          compensations[keeperId] += compensation;
        } else {
          payable(msg.sender).transfer(compensation);
        }

        // Update lastExecutionAt for interval jobs
        {
          uint256 intervalSeconds = (binJob << 32) >> 232;
          if (intervalSeconds > 0) {
            uint256 lastExecutionAt = uint32(block.timestamp);
            binJob = binJob & BM_CLEAR_LAST_UPDATE_AT | (lastExecutionAt << 224);
            jobChanged = true;
          }
        }

        if (jobChanged) {
          _updateRawJob(jobKey, binJob);
        }
      }

      emit Execute(
        jobKey,
        jobAddress,
        keeperId,
        gasUsed,
        block.basefee,
        tx.gasprice,
        compensation,
        bytes32(binJob)
      );
    // Tx reverted
    } else {
      uint256 size;
      assembly ("memory-safe") {
        size := returndatasize()
      }

      if (size == 0) {
        revert JobCallRevertedWithoutDetails();
      }

      assembly ("memory-safe") {
        let p := mload(0x40)
        returndatacopy(p, 0, size)
        revert(p, size)
      }
    }
  }

  function _calculateCompensation(uint256 job_, uint256 gasPrice_, uint256 gasUsed_) internal pure returns (uint256) {
    uint256 fixedReward = (job_ << 64) >> 224;
    uint256 rewardPct = (job_ << 96) >> 240;
    return calculateCompensationPure(rewardPct, fixedReward, gasPrice_, gasUsed_);
  }

  function _useJobOwnerCredits(bytes32 jobKey_, uint256 compensation_) internal {
    uint256 jobOwnerCreditsBefore = jobOwnerCredits[jobOwners[jobKey_]];
    if (jobOwnerCreditsBefore < compensation_) {
      revert InsufficientJobOwnerCredits(jobOwnerCreditsBefore, compensation_);
    }

    unchecked {
      jobOwnerCredits[jobOwners[jobKey_]] = jobOwnerCreditsBefore - compensation_;
    }
  }

  struct RegisterJobParams {
    address jobAddress;
    bytes4 jobSelector;
    bool useJobOwnerCredits;
    bool assertResolverSelector;
    uint16 maxBaseFeeGwei;
    uint16 rewardPct;
    uint32 fixedReward;
    uint256 jobMinCvp;
    uint8 calldataSource;
    uint24 intervalSeconds;
  }

  /*** JOB OWNER INTERFACE ***/

  /**
   * Registers a new job.
   *
   * Job id is unique counter for a given job address. Up to 2**24-1 jobs per address.
   * Job key is a keccak256(address, jobId).
   * The following options are immutable:
   *  - `params_.jobaddress`
   *  - `params_.calldataSource`
   * If you need to modify one of the immutable options above later consider creating a new job.
   *
   * @param params_ Job-specific params
   * @param resolver_ Resolver details(address, calldata), required only for CALLDATA_SOURCE_RESOLVER
   *                  job type. Use empty values for the other job types.
   * @param preDefinedCalldata_ Calldata to call a job with, required only for CALLDATA_SOURCE_PRE_DEFINED
   *              job type. Keep empty for the other job types.
   */
  function registerJob(
    RegisterJobParams calldata params_,
    Resolver calldata resolver_,
    bytes calldata preDefinedCalldata_
  ) external payable returns (bytes32 jobKey, uint256 jobId){
    jobId = jobNextIds[params_.jobAddress];

    if (jobId > type(uint24).max) {
      revert JobIdOverflow();
    }

    if (msg.value > type(uint88).max) {
      revert CreditsDepositOverflow();
    }

    if (params_.jobAddress == address(0)) {
      revert MissingJobAddress();
    }

    if (params_.calldataSource > 2) {
      revert InvalidCalldataSource();
    }

    if (params_.jobAddress == address(CVP)) {
      revert InvalidJobAddress();
    }

    _assertInterval(params_.intervalSeconds, CalldataSourceType(params_.calldataSource));
    _assertJobParams(params_.maxBaseFeeGwei, params_.fixedReward, params_.rewardPct);
    jobKey = getJobKey(params_.jobAddress, jobId);

    emit RegisterJob(
      jobKey,
      params_.jobAddress,
      params_.jobSelector,
      params_.useJobOwnerCredits,
      msg.sender,
      params_.jobMinCvp,
      params_.maxBaseFeeGwei,
      params_.rewardPct,
      params_.fixedReward,
      params_.calldataSource
    );

    if (CalldataSourceType(params_.calldataSource) == CalldataSourceType.PRE_DEFINED) {
      _setJobPreDefinedCalldata(jobKey, preDefinedCalldata_);
    } else if (CalldataSourceType(params_.calldataSource) == CalldataSourceType.RESOLVER) {
      _setJobResolver(jobKey, resolver_);
    }

    {
      bytes4 selector = 0x00000000;
      if (CalldataSourceType(params_.calldataSource) != CalldataSourceType.PRE_DEFINED) {
        selector = params_.jobSelector;
      }

      uint256 config = CFG_ACTIVE;
      if (params_.useJobOwnerCredits) {
        config = config | CFG_USE_JOB_OWNER_CREDITS;
      }
      if (params_.assertResolverSelector) {
        config = config | CFG_ASSERT_RESOLVER_SELECTOR;
      }
      if (params_.jobMinCvp > 0) {
        config = config | CFG_CHECK_KEEPER_MIN_CVP_DEPOSIT;
      }

      jobs[jobKey] = Job({
        config: uint8(config),
        selector: selector,
        credits: 0,
        maxBaseFeeGwei: params_.maxBaseFeeGwei,
        fixedReward: params_.fixedReward,
        rewardPct: params_.rewardPct,
        calldataSource: params_.calldataSource,

        // For interval jobs
        intervalSeconds: params_.intervalSeconds,
        lastExecutionAt: 0
      });
      jobMinKeeperCvp[jobKey] = params_.jobMinCvp;
    }

    jobNextIds[params_.jobAddress] += 1;
    jobOwners[jobKey] = msg.sender;

    if (msg.value > 0) {
      if (params_.useJobOwnerCredits) {
        _processJobOwnerCreditsDeposit(msg.sender);
      } else {
        _processJobCreditsDeposit(jobKey);
      }
    }
  }

  /**
   * Updates a job details.
   *
   * The following options are immutable:
   *  - `jobAddress`
   *  - `job.selector`
   *  - `job.calldataSource`
   * If you need to modify one of the immutable options above later consider creating a new job.
   *
   * @param jobKey_ The job key
   * @param maxBaseFeeGwei_ The maximum basefee in gwei to use for a job compensation
   * @param rewardPct_ The reward premium in pct, where 1 == 1%
   * @param fixedReward_ The fixed reward divided by FIXED_PAYMENT_MULTIPLIER
   * @param jobMinCvp_ The keeper minimal CVP stake to be eligible to execute this job
   * @param intervalSeconds_ The interval for a job execution
   */
  function updateJob(
    bytes32 jobKey_,
    uint16 maxBaseFeeGwei_,
    uint16 rewardPct_,
    uint32 fixedReward_,
    uint256 jobMinCvp_,
    uint24 intervalSeconds_
  ) external {
    _assertOnlyJobOwner(jobKey_);
    _assertJobParams(maxBaseFeeGwei_, fixedReward_, rewardPct_);

    Job memory job = jobs[jobKey_];

    _assertInterval(intervalSeconds_, CalldataSourceType(job.calldataSource));

    uint256 cfg = job.config;

    if (jobMinCvp_ > 0 && !ConfigFlags.check(job.config, CFG_CHECK_KEEPER_MIN_CVP_DEPOSIT)) {
      cfg = cfg | CFG_CHECK_KEEPER_MIN_CVP_DEPOSIT;
    }
    if (jobMinCvp_ == 0 && ConfigFlags.check(job.config, CFG_CHECK_KEEPER_MIN_CVP_DEPOSIT)) {
      cfg = cfg ^ CFG_CHECK_KEEPER_MIN_CVP_DEPOSIT;
    }

    jobs[jobKey_].config = uint8(cfg);
    jobMinKeeperCvp[jobKey_] = jobMinCvp_;

    jobs[jobKey_].maxBaseFeeGwei = maxBaseFeeGwei_;
    jobs[jobKey_].rewardPct = rewardPct_;
    jobs[jobKey_].fixedReward = fixedReward_;
    jobs[jobKey_].intervalSeconds = intervalSeconds_;

    emit JobUpdate(jobKey_, maxBaseFeeGwei_, rewardPct_, fixedReward_, jobMinCvp_, intervalSeconds_);
  }

  /**
   * A job owner updates job resolver details.
   *
   * @param jobKey_ The jobKey
   * @param resolver_ The new job resolver details
   */
  function setJobResolver(bytes32 jobKey_, Resolver calldata resolver_) external {
    _assertOnlyJobOwner(jobKey_);
    _assertJobCalldataSource(jobKey_, CalldataSourceType.RESOLVER);

    _setJobResolver(jobKey_, resolver_);
  }

  function _setJobResolver(bytes32 jobKey_, Resolver calldata resolver_) internal {
    if (resolver_.resolverAddress == address(0)) {
      revert MissingResolverAddress();
    }
    resolvers[jobKey_] = resolver_;
    emit SetJobResolver(jobKey_, resolver_.resolverAddress, resolver_.resolverCalldata);
  }

  /**
   * A job owner updates pre-defined calldata.
   *
   * @param jobKey_ The jobKey
   * @param preDefinedCalldata_ The new job pre-defined calldata
   */
  function setJobPreDefinedCalldata(bytes32 jobKey_, bytes calldata preDefinedCalldata_) external {
    _assertOnlyJobOwner(jobKey_);
    _assertJobCalldataSource(jobKey_, CalldataSourceType.PRE_DEFINED);

    _setJobPreDefinedCalldata(jobKey_, preDefinedCalldata_);
  }

  function _setJobPreDefinedCalldata(bytes32 jobKey_, bytes calldata preDefinedCalldata_) internal {
    preDefinedCalldatas[jobKey_] = preDefinedCalldata_;
    emit SetJobPreDefinedCalldata(jobKey_, preDefinedCalldata_);
  }

  /**
   * A job owner updates a job config flag.
   *
   * @param jobKey_ The jobKey
   * @param isActive_ Whether the job is active or not
   * @param useJobOwnerCredits_ The useJobOwnerCredits flag
   * @param assertResolverSelector_ The assertResolverSelector flag
   */
  function setJobConfig(
    bytes32 jobKey_,
    bool isActive_,
    bool useJobOwnerCredits_,
    bool assertResolverSelector_
  ) external {
    _assertOnlyJobOwner(jobKey_);
    uint256 newConfig = 0;

    if (isActive_) {
      newConfig = newConfig | CFG_ACTIVE;
    }
    if (useJobOwnerCredits_) {
      newConfig = newConfig | CFG_USE_JOB_OWNER_CREDITS;
    }
    if (assertResolverSelector_) {
      newConfig = newConfig | CFG_ASSERT_RESOLVER_SELECTOR;
    }

    uint256 job = getJobRaw(jobKey_) & BM_CLEAR_CONFIG | newConfig;
    _updateRawJob(jobKey_, job);

    emit SetJobConfig(jobKey_, isActive_, useJobOwnerCredits_, assertResolverSelector_);
  }

  function _updateRawJob(bytes32 jobKey_, uint256 job_) internal {
    Job storage job = jobs[jobKey_];
    assembly {
      sstore(job.slot, job_)
    }
  }

  /**
   * A job owner initiates the job transfer to a new owner.
   * The actual owner doesn't update until the pending owner accepts the transfer.
   *
   * @param jobKey_ The jobKey
   * @param to_ The new job owner
   */
  function initiateJobTransfer(bytes32 jobKey_, address to_) external {
    _assertOnlyJobOwner(jobKey_);
    jobPendingTransfers[jobKey_] = to_;
    emit InitiateJobTransfer(jobKey_, msg.sender, to_);
  }

  /**
   * A pending job owner accepts the job transfer.
   *
   * @param jobKey_ The jobKey
   */
  function acceptJobTransfer(bytes32 jobKey_) external {
    if (msg.sender != jobPendingTransfers[jobKey_]) {
      revert OnlyPendingOwner();
    }

    jobOwners[jobKey_] = msg.sender;
    delete jobPendingTransfers[jobKey_];

    emit AcceptJobTransfer(jobKey_, msg.sender);
  }

  /**
   * Top-ups the job credits in NATIVE tokens.
   *
   * @param jobKey_ The jobKey to deposit for
   */
  function depositJobCredits(bytes32 jobKey_) external payable {
    _assertNonZeroValue();

    if (jobOwners[jobKey_] == address(0)) {
      revert JobWithoutOwner();
    }

    _processJobCreditsDeposit(jobKey_);
  }

  function _processJobCreditsDeposit(bytes32 jobKey_) internal {
    (uint256 fee, uint256 amount) = _calculateDepositFee();
    uint256 creditsAfter = jobs[jobKey_].credits + amount;
    if (creditsAfter > type(uint88).max) {
      revert CreditsDepositOverflow();
    }

    unchecked {
      feeTotal += fee;
    }
    jobs[jobKey_].credits = uint88(creditsAfter);

    emit DepositJobCredits(jobKey_, msg.sender, amount, fee);
  }

  function _calculateDepositFee() internal view returns (uint256 fee, uint256 amount) {
    fee = msg.value * feePpm / 1e6 /* 100% in ppm */;
    amount = msg.value - fee;
  }

  /**
   * A job owner withdraws the job credits in NATIVE tokens.
   *
   * @param jobKey_ The jobKey
   * @param to_ The address to send NATIVE tokens to
   * @param amount_ The amount to withdraw. Use type(uint256).max for the total available credits withdrawal.
   */
  function withdrawJobCredits(
    bytes32 jobKey_,
    address payable to_,
    uint256 amount_
  ) external {
    uint88 creditsBefore = jobs[jobKey_].credits;
    if (amount_ == type(uint256).max) {
      amount_ = creditsBefore;
    }

    _assertOnlyJobOwner(jobKey_);
    _assertNonZeroAmount(amount_);

    if (creditsBefore < amount_) {
      revert CreditsWithdrawalUnderflow();
    }

    unchecked {
      jobs[jobKey_].credits = creditsBefore - uint88(amount_);
    }

    to_.transfer(amount_);

    emit WithdrawJobCredits(jobKey_, msg.sender, to_, amount_);
  }

  /**
   * Top-ups the job owner credits in NATIVE tokens.
   *
   * @param for_ The job owner address to deposit for
   */
  function depositJobOwnerCredits(address for_) external payable {
    _assertNonZeroValue();

    _processJobOwnerCreditsDeposit(for_);
  }

  function _processJobOwnerCreditsDeposit(address for_) internal {
    (uint256 fee, uint256 amount) = _calculateDepositFee();

    unchecked {
      feeTotal += fee;
      jobOwnerCredits[for_] += amount;
    }

    emit DepositJobOwnerCredits(for_, msg.sender, amount, fee);
  }

  /**
   * A job owner withdraws the job owner credits in NATIVE tokens.
   *
   * @param to_ The address to send NATIVE tokens to
   * @param amount_ The amount to withdraw. Use type(uint256).max for the total available credits withdrawal.
   */
  function withdrawJobOwnerCredits(address payable to_, uint256 amount_) external {
    uint256 creditsBefore = jobOwnerCredits[msg.sender];
    if (amount_ == type(uint256).max) {
      amount_ = creditsBefore;
    }

    _assertNonZeroAmount(amount_);

    if (creditsBefore < amount_) {
      revert CreditsWithdrawalUnderflow();
    }

    unchecked {
      jobOwnerCredits[msg.sender] = creditsBefore - amount_;
    }

    to_.transfer(amount_);

    emit WithdrawJobOwnerCredits(msg.sender, to_, amount_);
  }

  /*** KEEPER INTERFACE ***/

  /**
   * Actor registers as a keeper.
   * One keeper address could have multiple keeper IDs. Requires at least `minKeepCvp` as an initial CVP deposit.
   *
   * @dev Overflow-safe only for CVP which total supply is less than type(uint96).max
   * @dev Maximum 2^24-1 keepers supported. There is no explicit check for overflow, but the keepers with ID >= 2^24
   *         won't be able to perform upkeep operations.
   *
   * @param worker_ The worker address
   * @param initialDepositAmount_ The initial CVP deposit. Should be no less than `minKeepCvp`
   * @return keeperId The registered keeper ID
   */
  function registerAsKeeper(address worker_, uint256 initialDepositAmount_) external returns (uint256 keeperId) {
    if (initialDepositAmount_ < minKeeperCvp) {
      revert InsufficientAmount();
    }

    keeperId = nextKeeperId++;
    keeperAdmins[keeperId] = msg.sender;
    keepers[keeperId] = Keeper(worker_, 0);
    emit RegisterAsKeeper(keeperId, msg.sender, worker_);

    _stake(keeperId, msg.sender, initialDepositAmount_);
  }

  /**
   * A keeper updates a keeper worker address
   *
   * @param keeperId_ The keeper ID
   * @param worker_ The new worker address
   */
  function setWorkerAddress(uint256 keeperId_, address worker_) external {
    _assertOnlyKeeperAdmin(keeperId_);

    keepers[keeperId_].worker = worker_;
    emit SetWorkerAddress(keeperId_, worker_);
  }

  /**
   * A keeper withdraws NATIVE token rewards.
   *
   * @param keeperId_ The keeper ID
   * @param to_ The address to withdraw to
   * @param amount_ The amount to withdraw. Use type(uint256).max for the total available compensation withdrawal.
   */
  function withdrawCompensation(uint256 keeperId_, address payable to_, uint256 amount_) external {
    uint256 available = compensations[keeperId_];
    if (amount_ == type(uint256).max) {
      amount_ = available;
    }

    _assertNonZeroAmount(amount_);
    _assertOnlyKeeperAdmin(keeperId_);

    if (amount_ > available) {
      revert WithdrawAmountExceedsAvailable(amount_, available);
    }

    unchecked {
      compensations[keeperId_] = available - amount_;
    }

    to_.transfer(amount_);

    emit WithdrawCompensation(keeperId_, to_, amount_);
  }

  /**
   * Deposits CVP for the given keeper ID. The beneficiary receives a derivative erc20 token in exchange of CVP.
   *   Accounts the staking amount on the beneficiary's stakeOf balance.
   *
   * @param keeperId_ The keeper ID
   * @param for_ The address receives derivative ERC20 tokens in exchange
   * @param amount_ The amount to stake
   */
  function stake(uint256 keeperId_, address for_, uint256 amount_) external {
    _assertNonZeroAmount(amount_);
    _stake(keeperId_, for_, amount_);
  }

  function _stake(uint256 keeperId_, address for_, uint256 amount_) internal {
    CVP.transferFrom(msg.sender, address(this), amount_);
    _mint(for_, amount_);
    keepers[keeperId_].cvpStake += uint96(amount_);

    emit Stake(keeperId_, amount_, msg.sender, for_);
  }

  /**
   * A keeper initiates CVP withdrawal.
   * The given CVP amount needs to go through the cooldown stage. After the cooldown is complete this amount could be
   * withdrawn using `finalizeRedeem()` method.
   * The msg.sender burns the paCVP token in exchange of the corresponding CVP amount.
   * Accumulates the existing pending for withdrawal amounts and re-initiates cooldown period.
   * If there is any slashed amount for the msg.sender, it should be compensated within the first initiateRedeem transaction
   * by burning the equivalent amount of paCVP tokens. The remaining CVP tokens won't be redeemed unless the slashed
   * amount is compensated.
   *
   * @param keeperId_ The keeper ID
   * @param amount_ The amount to cooldown
   * @return pendingWithdrawalAfter The total pending for withdrawal amount
   */
  function initiateRedeem(uint256 keeperId_, uint256 amount_) external returns (uint256 pendingWithdrawalAfter) {
    _assertOnlyKeeperAdmin(keeperId_);
    _assertNonZeroAmount(amount_);

    uint256 stakeOfBefore = keepers[keeperId_].cvpStake;
    uint256 slashedStakeOfBefore = slashedStakeOf[keeperId_];
    uint256 totalStakeBefore = stakeOfBefore + slashedStakeOfBefore;

    // Should burn at least the total slashed stake
    if (amount_ < slashedStakeOfBefore) {
      revert InsufficientAmountToCoverSlashedStake(amount_, slashedStakeOfBefore);
    }

    if (amount_ > totalStakeBefore) {
      revert AmountGtStake(amount_, stakeOfBefore, slashedStakeOfBefore);
    }

    _burn(msg.sender, amount_);
    slashedStakeOf[keeperId_] = 0;
    uint256 stakeOfToReduceAmount;
    unchecked {
      stakeOfToReduceAmount = amount_ - slashedStakeOfBefore;
      keepers[keeperId_].cvpStake = uint96(stakeOfBefore - stakeOfToReduceAmount);
      pendingWithdrawalAmounts[keeperId_] += stakeOfToReduceAmount;
    }

    pendingWithdrawalAfter = block.timestamp + pendingWithdrawalTimeoutSeconds;
    pendingWithdrawalEndsAt[keeperId_] = pendingWithdrawalAfter;

    emit InitiateRedeem(keeperId_, amount_, stakeOfToReduceAmount, slashedStakeOfBefore);
  }

  /**
   * A keeper finalizes CVP withdrawal and receives the staked CVP tokens.
   *
   * @param keeperId_ The keeper ID
   * @param to_ The address to transfer CVP to
   * @return redeemedCvp The redeemed CVP amount
   */
  function finalizeRedeem(uint256 keeperId_, address to_) external returns (uint256 redeemedCvp) {
    _assertOnlyKeeperAdmin(keeperId_);

    if (pendingWithdrawalEndsAt[keeperId_] > block.timestamp) {
      revert WithdrawalTimoutNotReached();
    }

    redeemedCvp = pendingWithdrawalAmounts[keeperId_];
    if (redeemedCvp == 0) {
      revert NoPendingWithdrawal();
    }

    pendingWithdrawalAmounts[keeperId_] = 0;
    CVP.transfer(to_, redeemedCvp);

    emit FinalizeRedeem(keeperId_, to_, redeemedCvp);
  }

  /*** CONTRACT OWNER INTERFACE ***/
  /**
   * Slashes any keeper_ for an amount within keeper's deposit.
   * Penalises a keeper for malicious behaviour like sandwitching upkeep transactions.
   *
   * @param keeperId_ The keeper ID to slash
   * @param to_ The address to send the slashed CVP to
   * @param currentAmount_ The amount to slash from the current keeper.cvpStake balance
   * @param pendingAmount_ The amount to slash from the pendingWithdrawals balance
   */
  function slash(uint256 keeperId_, address to_, uint256 currentAmount_, uint256 pendingAmount_) external {
    _assertOnlyOwner();
    uint256 totalAmount = currentAmount_ + pendingAmount_;
    _assertNonZeroAmount(totalAmount);

    if (currentAmount_ > 0) {
      keepers[keeperId_].cvpStake -= uint96(currentAmount_);
      slashedStakeOf[keeperId_] += currentAmount_;
    }

    if (pendingAmount_ > 0) {
      pendingWithdrawalAmounts[keeperId_] -= pendingAmount_;
    }

    CVP.transfer(to_, totalAmount);

    emit Slash(keeperId_, to_, currentAmount_, pendingAmount_);
  }

  /**
   * Owner withdraws all the accrued rewards in native tokens to the provided address.
   *
   * @param to_ The address to send rewards to
   */
  function withdrawFees(address payable to_) external {
    _assertOnlyOwner();

    uint256 amount = feeTotal;
    feeTotal = 0;

    to_.transfer(amount);

    emit WithdrawFees(to_, amount);
  }

  /**
   * Owner updates minKeeperCVP value
   *
   * @param minKeeperCvp_ The new minKeeperCVP value
   */
  function setAgentParams(
    uint256 minKeeperCvp_,
    uint256 timeoutSeconds_,
    uint256 feePpm_
  ) external {
    _assertOnlyOwner();

    if (timeoutSeconds_ > MAX_PENDING_WITHDRAWAL_TIMEOUT_SECONDS) {
      revert TimeoutTooBig();
    }
    if (feePpm_ > MAX_FEE_PPM) {
      revert FeeTooBig();
    }

    minKeeperCvp = minKeeperCvp_;
    pendingWithdrawalTimeoutSeconds = timeoutSeconds_;
    feePpm = feePpm_;

    emit SetAgentParams(minKeeperCvp_, timeoutSeconds_, feePpm_);
  }

  /*** GETTERS ***/

  /**
   * Pure method that calculates keeper compensation based on a dynamic and a fixed multipliers.
   * DANGER: could overflow when used externally
   *
   * @param rewardPct_ The fixed percent. uint16. 0 == 0%, 100 == 100%, 500 == 500%, max 56535 == 56535%
   * @param fixedReward_ The fixed reward. uint32. Always multiplied by 1e15 (FIXED_PAYMENT_MULTIPLIER).
   *                     For ex. 2 == 2e15, 1_000 = 1e18, max 4294967295 == 4_294_967.295e18
   * @param blockBaseFee_ The block.basefee value.
   * @param gasUsed_ The gas used in wei.
   *
   */
  function calculateCompensationPure(
    uint256 rewardPct_,
    uint256 fixedReward_,
    uint256 blockBaseFee_,
    uint256 gasUsed_
  ) public pure returns (uint256) {
    unchecked {
      return (gasUsed_ + JOB_RUN_GAS_OVERHEAD) * blockBaseFee_ * rewardPct_ / 100
             + fixedReward_ * FIXED_PAYMENT_MULTIPLIER;
    }
  }

  function getConfig()
    external view returns (
      uint256 minKeeperCvp_,
      uint256 pendingWithdrawalTimeoutSeconds_,
      uint256 feeTotal_,
      uint256 feePpm_
    )
  {
    return (
      minKeeperCvp,
      pendingWithdrawalTimeoutSeconds,
      feeTotal,
      feePpm
    );
  }

  function getKeeper(uint256 keeperId_)
    external view returns (
      address admin,
      address worker,
      uint256 currentStake,
      uint256 slashedStake,
      uint256 compensation,
      uint256 pendingWithdrawalAmount,
      uint256 pendingWithdrawalEndAt
    )
  {
    return (
      keeperAdmins[keeperId_],
      keepers[keeperId_].worker,
      keepers[keeperId_].cvpStake,
      slashedStakeOf[keeperId_],
      compensations[keeperId_],
      pendingWithdrawalAmounts[keeperId_],
      pendingWithdrawalEndsAt[keeperId_]
    );
  }

  function getJob(bytes32 jobKey_)
    external view returns (
      address owner,
      address pendingTransfer,
      uint256 jobLevelMinKeeperCvp,
      Job memory details,
      bytes memory preDefinedCalldata,
      Resolver memory resolver
    )
  {
    return (
      jobOwners[jobKey_],
      jobPendingTransfers[jobKey_],
      jobMinKeeperCvp[jobKey_],
      jobs[jobKey_],
      preDefinedCalldatas[jobKey_],
      resolvers[jobKey_]
    );
  }

  /**
   * Returns the principal job data stored in a single EVM slot.
   * @notice To get parsed job data use `getJob()` method instead.
   *
   * The job slot data layout:
   *  0x0000000000000a000000000a002300640000000de0b6b3a7640000d09de08a01
   *  0x      00000000   00000a   00             0000000a    0023      0064           0000000de0b6b3a7640000 d09de08a 01
   *  name    lastExecAt interval calldataSource fixedReward rewardPct maxBaseFeeGwei nativeCredits          selector config bitmask
   *  size b  bytes4     bytes3   bytes4         bytes4      bytes2    bytes2         bytes11                bytes4   bytes1
   *  size u  uint32     uint24   uint8          uint32      uint16    uint16         uint88                 uint32   uint8
   *  bits    0-3        4-6      7-7            8-11        12-13     14-15          16-26                  27-30    31-31
   */
  function getJobRaw(bytes32 jobKey_) public view returns (uint256 rawJob) {
    Job storage job = jobs[jobKey_];
    assembly {
      rawJob := sload(job.slot)
    }
  }

  function getJobKey(address jobAddress_, uint256 jobId_) public pure returns (bytes32 jobKey) {
    assembly {
      mstore(0, shl(96, jobAddress_))
      mstore(20, shl(232, jobId_))
      jobKey := keccak256(0, 23)
    }
  }
}
