// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import "./TransferHelper.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./IBEP20.sol";
interface IPancakeswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
interface IPresaleLockForwarder {
    function lockLiquidity (IBEP20 _baseToken, IBEP20 _saleToken, uint256 _baseAmount, uint256 _saleAmount, uint256 _unlock_date, address payable _withdrawer) external;
    function pancakeswapPairIsInitialised (address _token0, address _token1) external view returns (bool);
}
interface IWBNB {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}
interface IPresaleSettings {
    function getMaxPresaleLength () external view returns (uint256);
    function getRound1Length () external view returns (uint256);
    function userHoldsSufficientRound1Token (address _user) external view returns (bool);
    function referrerIsValid(address _referrer) external view returns (bool);
    function getBaseFee () external view returns (uint256);
    function getTokenFee () external view returns (uint256);
    function getBnbAddress () external view returns (address payable);
    function getTokenAddress () external view returns (address payable);
    function getReferralFee () external view returns (uint256);
    function getBnbCreationFee () external view returns (uint256);
}
contract Presale is ReentrancyGuard {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  /// @notice Presale Contract Version, used to choose the correct ABI to decode the contract
  uint256 public CONTRACT_VERSION = 1;
  struct PresaleInfo {
    address payable PRESALE_OWNER;
    IBEP20 S_TOKEN; // sale token
    IBEP20 B_TOKEN; // base token // usually WBNB (BNB)
    uint256 TOKEN_PRICE; // 1 base token = ? s_tokens, fixed price
    uint256 MAX_SPEND_PER_BUYER; // maximum base token BUY amount per account
    uint256 AMOUNT; // the amount of presale tokens up for presale
    uint256 HARDCAP;
    uint256 SOFTCAP;
    uint256 LIQUIDITY_PERCENT; // divided by 1000
    uint256 LISTING_RATE; // fixed rate at which the token will list on Pancakeswap
    uint256 START_BLOCK;
    uint256 END_BLOCK;
    uint256 LOCK_PERIOD; // unix timestamp -> e.g. 2 weeks
    bool PRESALE_IN_BNB; // if this flag is true the presale is raising BNB, otherwise an BEP20 token such as DAI
  }
  struct PresaleFeeInfo {
    uint256 SMART_BASE_FEE; // divided by 1000
    uint256 SMART_TOKEN_FEE; // divided by 1000
    uint256 REFERRAL_FEE; // divided by 1000
    address payable BASE_FEE_ADDRESS;
    address payable TOKEN_FEE_ADDRESS;
    address payable REFERRAL_FEE_ADDRESS; // if this is not address(0), there is a valid referral
  }
  struct PresaleStatus {
    bool WHITELIST_ONLY; // if set to true only whitelisted members may participate
    bool LP_GENERATION_COMPLETE; // final flag required to end a presale and enable withdrawls
    bool FORCE_FAILED; // set this flag to force fail the presale
    uint256 TOTAL_BASE_COLLECTED; // total base currency raised (usually BNB)
    uint256 TOTAL_TOKENS_SOLD; // total presale tokens sold
    uint256 TOTAL_TOKENS_WITHDRAWN; // total tokens withdrawn post successful presale
    uint256 TOTAL_BASE_WITHDRAWN; // total base tokens withdrawn on presale failure
    uint256 ROUND1_LENGTH; // in blocks
    uint256 NUM_BUYERS; // number of unique participants
  }
  struct BuyerInfo {
    uint256 baseDeposited; // total base token (usually BNB) deposited by user, can be withdrawn on presale failure
    uint256 tokensOwed; // num presale tokens a user is owed, can be withdrawn on presale success
  }
  PresaleInfo public PRESALE_INFO;
  PresaleFeeInfo public PRESALE_FEE_INFO;
  PresaleStatus public STATUS;
  address public PRESALE_GENERATOR;
  IPresaleLockForwarder public PRESALE_LOCK_FORWARDER;
  IPresaleSettings public PRESALE_SETTINGS;
  address payable SMART_FEE_ADDRESS;
  IPancakeswapV2Factory public PANCAKESWAPV2_FACTORY;
  IWBNB public WBNB;
  mapping(address => BuyerInfo) public BUYERS;
  EnumerableSet.AddressSet private WHITELIST;
  constructor(address _presaleGenerator,IPancakeswapV2Factory _PANCAKESWAPV2_FACTORY,IWBNB _WBNB,IPresaleSettings _PRESALE_SETTINGS,IPresaleLockForwarder _PRESALE_LOCK_FORWARDER, address payable _SMART_FEE_ADDRESS) public {
    PRESALE_GENERATOR = _presaleGenerator;
    PANCAKESWAPV2_FACTORY = _PANCAKESWAPV2_FACTORY;
    WBNB = _WBNB;
    PRESALE_SETTINGS = _PRESALE_SETTINGS;
    PRESALE_LOCK_FORWARDER = _PRESALE_LOCK_FORWARDER;
    SMART_FEE_ADDRESS = _SMART_FEE_ADDRESS;
  }
  function StartPresale (
    address payable _presaleOwner, 
    IBEP20 _presaleToken,
    uint256 _amount,
    uint256 _tokenPrice, 
    uint256 _maxBnbPerBuyer, 
    uint256 _hardcap, 
    uint256 _softcap,
    uint256 _liquidityPercent,
    uint256 _listingRate,
    uint256 _startblock,
    uint256 _endblock,
    uint256 _lockPeriod
    ) external {
      require(msg.sender == PRESALE_GENERATOR, 'FORBIDDEN');
      PRESALE_INFO.PRESALE_OWNER = _presaleOwner;
      PRESALE_INFO.S_TOKEN = _presaleToken;
      PRESALE_INFO.AMOUNT = _amount;
      PRESALE_INFO.TOKEN_PRICE = _tokenPrice;
      PRESALE_INFO.MAX_SPEND_PER_BUYER = _maxBnbPerBuyer;
      PRESALE_INFO.HARDCAP = _hardcap;
      PRESALE_INFO.SOFTCAP = _softcap;
      PRESALE_INFO.LIQUIDITY_PERCENT = _liquidityPercent;
      PRESALE_INFO.LISTING_RATE = _listingRate;
      PRESALE_INFO.START_BLOCK = _startblock;
      PRESALE_INFO.END_BLOCK = _endblock;
      PRESALE_INFO.LOCK_PERIOD = _lockPeriod;
  }
  function Sale (
    IBEP20 _baseToken,
    IBEP20 _presaleToken,
    uint256 _pancakecryptBaseFee,
    uint256 _pancakecryptTokenFee,
    uint256 _referralFee,
    address payable _baseFeeAddress,
    address payable _tokenFeeAddress,
    address payable _referralAddress
    ) external {   
      require(msg.sender == PRESALE_GENERATOR, 'FORBIDDEN');
      // require(!PRESALE_LOCK_FORWARDER.pancakeswapPairIsInitialised(address(_presaleToken), address(_baseToken)), 'PAIR INITIALISED');
      PRESALE_INFO.PRESALE_IN_BNB = address(_baseToken) == address(WBNB);
      PRESALE_INFO.S_TOKEN = _presaleToken;
      PRESALE_INFO.B_TOKEN = _baseToken;
      PRESALE_FEE_INFO.SMART_BASE_FEE = _pancakecryptBaseFee;
      PRESALE_FEE_INFO.SMART_TOKEN_FEE = _pancakecryptTokenFee;
      PRESALE_FEE_INFO.REFERRAL_FEE = _referralFee;
      PRESALE_FEE_INFO.BASE_FEE_ADDRESS = _baseFeeAddress;
      PRESALE_FEE_INFO.TOKEN_FEE_ADDRESS = _tokenFeeAddress;
      PRESALE_FEE_INFO.REFERRAL_FEE_ADDRESS = _referralAddress;
      STATUS.ROUND1_LENGTH = PRESALE_SETTINGS.getRound1Length();
  }
  modifier onlyPresaleOwner() {
    require(PRESALE_INFO.PRESALE_OWNER == msg.sender, "NOT PRESALE OWNER");
    _;
  }
  function presaleStatus () public view returns (uint256) {
    if (STATUS.FORCE_FAILED) {
      return 3; // FAILED - force fail
    }
    if ((block.number > PRESALE_INFO.END_BLOCK) && (STATUS.TOTAL_BASE_COLLECTED < PRESALE_INFO.SOFTCAP)) {
      return 3; // FAILED - softcap not met by end block
    }
    if (STATUS.TOTAL_BASE_COLLECTED >= PRESALE_INFO.HARDCAP) {
      return 2; // SUCCESS - hardcap met
    }
    if ((block.number > PRESALE_INFO.END_BLOCK) && (STATUS.TOTAL_BASE_COLLECTED >= PRESALE_INFO.SOFTCAP)) {
      return 2; // SUCCESS - endblock and soft cap reached
    }
    if ((block.number >= PRESALE_INFO.START_BLOCK) && (block.number <= PRESALE_INFO.END_BLOCK)) {
      return 1; // ACTIVE - deposits enabled
    }
    return 0; // QUED - awaiting start block
  }
  // accepts msg.value for BNB or _amount for BEP20 tokens
  function userDeposit (uint256 _amount) external payable nonReentrant {
    require(presaleStatus() == 1, 'NOT ACTIVE'); // ACTIVE
    if (STATUS.WHITELIST_ONLY) {
      require(WHITELIST.contains(msg.sender), 'NOT WHITELISTED');
    }
    // Presale Round 1 - require participant to hold a certain token and balance
    if (block.number < PRESALE_INFO.START_BLOCK + STATUS.ROUND1_LENGTH) { // 276 blocks = 1 hour
        require(PRESALE_SETTINGS.userHoldsSufficientRound1Token(msg.sender), 'INSUFFICENT ROUND 1 TOKEN BALANCE');
    }
    BuyerInfo storage buyer = BUYERS[msg.sender];
    uint256 amount_in = PRESALE_INFO.PRESALE_IN_BNB ? msg.value : _amount;
    uint256 allowance = PRESALE_INFO.MAX_SPEND_PER_BUYER.sub(buyer.baseDeposited);
    uint256 remaining = PRESALE_INFO.HARDCAP - STATUS.TOTAL_BASE_COLLECTED;
    allowance = allowance > remaining ? remaining : allowance;
    if (amount_in > allowance) {
      amount_in = allowance;
    }
    uint256 tokensSold = amount_in.mul(PRESALE_INFO.TOKEN_PRICE).div(10 ** uint256(PRESALE_INFO.B_TOKEN.decimals()));
    require(tokensSold > 0, 'ZERO TOKENS');
    if (buyer.baseDeposited == 0) {
        STATUS.NUM_BUYERS++;
    }
    buyer.baseDeposited = buyer.baseDeposited.add(amount_in);
    buyer.tokensOwed = buyer.tokensOwed.add(tokensSold);
    STATUS.TOTAL_BASE_COLLECTED = STATUS.TOTAL_BASE_COLLECTED.add(amount_in);
    STATUS.TOTAL_TOKENS_SOLD = STATUS.TOTAL_TOKENS_SOLD.add(tokensSold);
    // return unused BNB
    if (PRESALE_INFO.PRESALE_IN_BNB && amount_in < msg.value) {
      (payable(msg.sender)).transfer(msg.value.sub(amount_in));
    }
    // deduct non BNB token from user
    if (!PRESALE_INFO.PRESALE_IN_BNB) {
      TransferHelper.safeTransferFrom(address(PRESALE_INFO.B_TOKEN), msg.sender, address(this), amount_in);
    }
  }
  // withdraw presale tokens
  // percentile withdrawls allows fee on transfer or rebasing tokens to still work
  function userWithdrawTokens () external nonReentrant {
    require(STATUS.LP_GENERATION_COMPLETE, 'AWAITING LP GENERATION');
    BuyerInfo storage buyer = BUYERS[msg.sender];
    uint256 tokensRemainingDenominator = STATUS.TOTAL_TOKENS_SOLD.sub(STATUS.TOTAL_TOKENS_WITHDRAWN);
    uint256 tokensOwed = PRESALE_INFO.S_TOKEN.balanceOf(address(this)).mul(buyer.tokensOwed).div(tokensRemainingDenominator);
    require(tokensOwed > 0, 'NOTHING TO WITHDRAW');
    STATUS.TOTAL_TOKENS_WITHDRAWN = STATUS.TOTAL_TOKENS_WITHDRAWN.add(buyer.tokensOwed);
    buyer.tokensOwed = 0;
    TransferHelper.safeTransfer(address(PRESALE_INFO.S_TOKEN), msg.sender, tokensOwed);
  }
  // on presale failure
  // percentile withdrawls allows fee on transfer or rebasing tokens to still work
  function userWithdrawBaseTokens () external nonReentrant {
    require(presaleStatus() == 3, 'NOT FAILED'); // FAILED
    BuyerInfo storage buyer = BUYERS[msg.sender];
    uint256 baseRemainingDenominator = STATUS.TOTAL_BASE_COLLECTED.sub(STATUS.TOTAL_BASE_WITHDRAWN);
    uint256 remainingBaseBalance = PRESALE_INFO.PRESALE_IN_BNB ? address(this).balance : PRESALE_INFO.B_TOKEN.balanceOf(address(this));
    uint256 tokensOwed = remainingBaseBalance.mul(buyer.baseDeposited).div(baseRemainingDenominator);
    require(tokensOwed > 0, 'NOTHING TO WITHDRAW');
    STATUS.TOTAL_BASE_WITHDRAWN = STATUS.TOTAL_BASE_WITHDRAWN.add(buyer.baseDeposited);
    buyer.baseDeposited = 0;
    TransferHelper.safeTransferBaseToken(address(PRESALE_INFO.B_TOKEN), payable(msg.sender), tokensOwed, !PRESALE_INFO.PRESALE_IN_BNB);
  }
  // on presale failure
  // allows the owner to withdraw the tokens they sent for presale & initial liquidity
  function ownerWithdrawTokens () external onlyPresaleOwner {
    require(presaleStatus() == 3); // FAILED
    TransferHelper.safeTransfer(address(PRESALE_INFO.S_TOKEN), PRESALE_INFO.PRESALE_OWNER, PRESALE_INFO.S_TOKEN.balanceOf(address(this)));
  }
  function forceFailIfPairExists () external {
    require(!STATUS.LP_GENERATION_COMPLETE && !STATUS.FORCE_FAILED);
    if (PRESALE_LOCK_FORWARDER.pancakeswapPairIsInitialised(address(PRESALE_INFO.S_TOKEN), address(PRESALE_INFO.B_TOKEN))) {
        STATUS.FORCE_FAILED = true;
    }
  }
  // if something goes wrong in LP generation
  function forceFailBySMART () external {
      require(msg.sender == SMART_FEE_ADDRESS);
      STATUS.FORCE_FAILED = true;
  }
  function addLiquidity() external nonReentrant {
    require(!STATUS.LP_GENERATION_COMPLETE, 'GENERATION COMPLETE');
    require(presaleStatus() == 2, 'NOT SUCCESS'); // SUCCESS
    // Fail the presale if the pair exists and contains presale token liquidity
    if (PRESALE_LOCK_FORWARDER.pancakeswapPairIsInitialised(address(PRESALE_INFO.S_TOKEN), address(PRESALE_INFO.B_TOKEN))) {
        STATUS.FORCE_FAILED = true;
        return;
    }
    uint256 pancakecryptBaseFee = STATUS.TOTAL_BASE_COLLECTED.mul(PRESALE_FEE_INFO.SMART_BASE_FEE).div(1000);
    // base token liquidity
    uint256 baseLiquidity = STATUS.TOTAL_BASE_COLLECTED.sub(pancakecryptBaseFee).mul(PRESALE_INFO.LIQUIDITY_PERCENT).div(1000);
    if (PRESALE_INFO.PRESALE_IN_BNB) {
        WBNB.deposit{value : baseLiquidity}();
    }
    TransferHelper.safeApprove(address(PRESALE_INFO.B_TOKEN), address(PRESALE_LOCK_FORWARDER), baseLiquidity);
    // sale token liquidity
    uint256 tokenLiquidity = baseLiquidity.mul(PRESALE_INFO.LISTING_RATE).div(10 ** uint256(PRESALE_INFO.B_TOKEN.decimals()));
    TransferHelper.safeApprove(address(PRESALE_INFO.S_TOKEN), address(PRESALE_LOCK_FORWARDER), tokenLiquidity);
    PRESALE_LOCK_FORWARDER.lockLiquidity(PRESALE_INFO.B_TOKEN, PRESALE_INFO.S_TOKEN, baseLiquidity, tokenLiquidity, block.timestamp + PRESALE_INFO.LOCK_PERIOD, PRESALE_INFO.PRESALE_OWNER);
    // transfer fees
    uint256 pancakecryptTokenFee = STATUS.TOTAL_TOKENS_SOLD.mul(PRESALE_FEE_INFO.SMART_TOKEN_FEE).div(1000);
    // referrals are checked for validity in the presale generator
    if (PRESALE_FEE_INFO.REFERRAL_FEE_ADDRESS != address(0)) {
        // Base token fee
        uint256 referralBaseFee = pancakecryptBaseFee.mul(PRESALE_FEE_INFO.REFERRAL_FEE).div(1000);
        TransferHelper.safeTransferBaseToken(address(PRESALE_INFO.B_TOKEN), PRESALE_FEE_INFO.REFERRAL_FEE_ADDRESS, referralBaseFee, !PRESALE_INFO.PRESALE_IN_BNB);
        pancakecryptBaseFee = pancakecryptBaseFee.sub(referralBaseFee);
        // Token fee
        uint256 referralTokenFee = pancakecryptTokenFee.mul(PRESALE_FEE_INFO.REFERRAL_FEE).div(1000);
        TransferHelper.safeTransfer(address(PRESALE_INFO.S_TOKEN), PRESALE_FEE_INFO.REFERRAL_FEE_ADDRESS, referralTokenFee);
        pancakecryptTokenFee = pancakecryptTokenFee.sub(referralTokenFee);
    }
    TransferHelper.safeTransferBaseToken(address(PRESALE_INFO.B_TOKEN), PRESALE_FEE_INFO.BASE_FEE_ADDRESS, pancakecryptBaseFee, !PRESALE_INFO.PRESALE_IN_BNB);
    TransferHelper.safeTransfer(address(PRESALE_INFO.S_TOKEN), PRESALE_FEE_INFO.TOKEN_FEE_ADDRESS, pancakecryptTokenFee);
    // burn unsold tokens
    uint256 remainingSBalance = PRESALE_INFO.S_TOKEN.balanceOf(address(this));
    if (remainingSBalance > STATUS.TOTAL_TOKENS_SOLD) {
        uint256 burnAmount = remainingSBalance.sub(STATUS.TOTAL_TOKENS_SOLD);
        TransferHelper.safeTransfer(address(PRESALE_INFO.S_TOKEN), 0x000000000000000000000000000000000000dEaD, burnAmount);
    }
    // send remaining base tokens to presale owner
    uint256 remainingBaseBalance = PRESALE_INFO.PRESALE_IN_BNB ? address(this).balance : PRESALE_INFO.B_TOKEN.balanceOf(address(this));
    TransferHelper.safeTransferBaseToken(address(PRESALE_INFO.B_TOKEN), PRESALE_INFO.PRESALE_OWNER, remainingBaseBalance, !PRESALE_INFO.PRESALE_IN_BNB);
    STATUS.LP_GENERATION_COMPLETE = true;
  }
  function updateMaxSpendLimit(uint256 _maxSpend) external onlyPresaleOwner {
    PRESALE_INFO.MAX_SPEND_PER_BUYER = _maxSpend;
  }
  // postpone or bring a presale forward, this will only work when a presale is inactive.
  // i.e. current start block > block.number
  function updateBlocks(uint256 _startBlock, uint256 _endBlock) external onlyPresaleOwner {
    require(PRESALE_INFO.START_BLOCK > block.number);
    require(_endBlock.sub(_startBlock) <= PRESALE_SETTINGS.getMaxPresaleLength());
    PRESALE_INFO.START_BLOCK = _startBlock;
    PRESALE_INFO.END_BLOCK = _endBlock;
  }
  // editable at any stage of the presale
  function setWhitelistFlag(bool _flag) external onlyPresaleOwner {
    STATUS.WHITELIST_ONLY = _flag;
  }
  // editable at any stage of the presale
  function editWhitelist(address[] memory _users, bool _add) external onlyPresaleOwner {
    if (_add) {
        for (uint i = 0; i < _users.length; i++) {
          WHITELIST.Add(_users[i]);
        }
    } else {
        for (uint i = 0; i < _users.length; i++) {
          WHITELIST.remove(_users[i]);
        }
    }
  }
  // whitelist getters
  function getWhitelistedUsersLength () external view returns (uint256) {
    return WHITELIST.length();
  }
  function getWhitelistedUserAtIndex (uint256 _index) external view returns (address) {
    return WHITELIST.at(_index);
  }
  function getUserWhitelistStatus (address _user) external view returns (bool) {
    return WHITELIST.contains(_user);
  }
}