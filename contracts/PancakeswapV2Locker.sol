// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import "./TransferHelper.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./TransferHelper.sol";
import "./EnumerableSet.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Context.sol";
interface IPancakeswapV2Pair {
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
}
interface IBEPBurn {
    function burn(uint256 _amount) external;
    function approve(address spender, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}
interface IPancakeFactory {
    function getPair(address tokenA, address tokenB) external view returns (address);
}

interface IMigrator {
    function migrate(address lpToken, uint256 amount, uint256 unlockDate, address owner) external returns (bool);
}
contract PancakeswapV2Locker is Ownable, ReentrancyGuard {
  using SafeMath for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  IPancakeFactory public PancakeswapV2Factory;
  struct UserInfo {
    EnumerableSet.AddressSet lockedTokens; // records all tokens the user has locked
    mapping(address => uint256[]) locksForToken; // map bep20 address to lock id for that token
  }
  struct TokenLock {
    uint256 lockDate; // the date the token was locked
    uint256 amount; // the amount of tokens still locked (initialAmount minus withdrawls)
    uint256 initialAmount; // the initial lock amount
    uint256 unlockDate; // the date the token can be withdrawn
    uint256 lockID; // lockID nonce per Pancake pair
    address owner;
  }
  mapping(address => UserInfo) private users;
  EnumerableSet.AddressSet private lockedTokens;
  mapping(address => TokenLock[]) public tokenLocks; //map Pancakev2 pair to all its locks
  struct FeeStruct {
    uint256 bnbFee; // Small bnb fee to prevent spam on the platform
    IBEPBurn secondaryFeeToken; // UNCX or UNCL
    uint256 secondaryTokenFee; // optional, UNCX or UNCL
    uint256 secondaryTokenDiscount; // discount on liquidity fee for burning secondaryToken
    uint256 liquidityFee; // fee on Pancakev2 liquidity tokens
    uint256 referralPercent; // fee for referrals
    IBEPBurn referralToken; // token the refferer must hold to qualify as a referrer
    uint256 referralHold; // balance the referrer must hold to qualify as a referrer
    uint256 referralDiscount; // discount on flatrate fees for using a valid referral address
  }
  FeeStruct public gFees;
  EnumerableSet.AddressSet private feeWhitelist;
  address payable devaddr;
  IMigrator migrator;
  event onDeposit(address lpToken, address user, uint256 amount, uint256 lockDate, uint256 unlockDate);
  event onWithdraw(address lpToken, uint256 amount);
  constructor(IPancakeFactory _PancakeswapV2Factory)public{
    devaddr = payable (msg.sender);
    gFees.referralPercent = 0; //250- 25%
    gFees.bnbFee = 0; //1e18
    gFees.secondaryTokenFee = 0;//100e18
    gFees.secondaryTokenDiscount = 0; //200- 20%
    gFees.liquidityFee = 0; //10- 1%
    gFees.referralHold = 0; //10e18
    gFees.referralDiscount = 0; // 100-10%
    PancakeswapV2Factory = _PancakeswapV2Factory;
  }
  function setDev(address payable _devaddr) public onlyOwner {
    devaddr = _devaddr;
  }
  /**
   * @notice set the migrator contract which allows locked lp tokens to be migrated to Pancakeswap v3
   */
  function setMigrator(IMigrator _migrator) public onlyOwner {
    migrator = _migrator;
  }
  function setSecondaryFeeToken(address _secondaryFeeToken) public onlyOwner {
    gFees.secondaryFeeToken = IBEPBurn(_secondaryFeeToken);
  }
  /**
   * @notice referrers need to hold the specified token and hold amount to be elegible for referral fees
   */
  function setReferralTokenAndHold(IBEPBurn _referralToken, uint256 _hold) public onlyOwner {
    gFees.referralToken = _referralToken;
    gFees.referralHold = _hold;
  }
  function setFees(uint256 _referralPercent, uint256 _referralDiscount, uint256 _bnbFee, uint256 _secondaryTokenFee, uint256 _secondaryTokenDiscount, uint256 _liquidityFee) public onlyOwner {
    gFees.referralPercent = _referralPercent;
    gFees.referralDiscount = _referralDiscount;
    gFees.bnbFee = _bnbFee;
    gFees.secondaryTokenFee = _secondaryTokenFee;
    gFees.secondaryTokenDiscount = _secondaryTokenDiscount;
    gFees.liquidityFee = _liquidityFee;
  }
  /**
   * @notice whitelisted accounts dont pay flatrate fees on locking
   */
  function whitelistFeeAccount(address _user, bool _add) public onlyOwner {
    if (_add) {
      feeWhitelist.Add(_user);
    } else {
      feeWhitelist.remove(_user);
    }
  }
  function lockLPToken (address _lpToken, uint256 _amount, uint256 _unlock_date, address payable _referral, bool _fee_in_bnb, address payable _withdrawer) external payable nonReentrant {
    require(_unlock_date < 10000000000, 'TIMESTAMP INVALID'); // prevents errors when timestamp entered in milliseconds
    require(_amount > 0, 'INSUFFICIENT');
    // ensure this pair is a Pancakev2 pair by querying the factory
    IPancakeswapV2Pair lpair = IPancakeswapV2Pair(address(_lpToken));
    address factoryPairAddress = PancakeswapV2Factory.getPair(lpair.token0(), lpair.token1());
    require(factoryPairAddress == address(_lpToken), 'NOT PancakeV2');
    TransferHelper.safeTransferFrom(_lpToken, address(msg.sender), address(this), _amount);
    if (_referral != address(0) && address(gFees.referralToken) != address(0)) {
      require(gFees.referralToken.balanceOf(_referral) >= gFees.referralHold, 'INADEQUATE BALANCE');
    }
    // flatrate fees
    if (!feeWhitelist.contains(msg.sender)) {
      if (_fee_in_bnb) { // charge fee in bnb
        uint256 bnbFee = gFees.bnbFee;
        if (_referral != address(0)) {
         bnbFee = bnbFee.mul(1000 - gFees.referralDiscount).div(1000);
        }
        require(msg.value == bnbFee, 'FEE NOT MET');
        uint256 devFee = bnbFee;
        if (bnbFee != 0 && _referral != address(0)) { // referral fee
          uint256 referralFee = devFee.mul(gFees.referralPercent).div(1000);
          _referral.transfer(referralFee);
          devFee = devFee.sub(referralFee);
        }
        devaddr.transfer(devFee);
      } else { // charge fee in token
        uint256 burnFee = gFees.secondaryTokenFee;
        if (_referral != address(0)) {
          burnFee = burnFee.mul(1000 - gFees.referralDiscount).div(1000);
        }
        TransferHelper.safeTransferFrom(address(gFees.secondaryFeeToken), address(msg.sender), address(this), burnFee);
        if (gFees.referralPercent != 0 && _referral != address(0)) { // referral fee
          uint256 referralFee = burnFee.mul(gFees.referralPercent).div(1000);
          TransferHelper.safeApprove(address(gFees.secondaryFeeToken), _referral, referralFee);
          TransferHelper.safeTransfer(address(gFees.secondaryFeeToken), _referral, referralFee);
          burnFee = burnFee.sub(referralFee);
        }
        gFees.secondaryFeeToken.burn(burnFee);
      }
    } else if (msg.value > 0){
      // refund bnb if a whitelisted member sent it by mistake
      (payable(msg.sender)).transfer(msg.value);
    }
    // percent fee
    uint256 liquidityFee = _amount.mul(gFees.liquidityFee).div(1000);
    if (!_fee_in_bnb && !feeWhitelist.contains(msg.sender)) { // fee discount for large lockers using secondary token
      liquidityFee = liquidityFee.mul(1000 - gFees.secondaryTokenDiscount).div(1000);
    }
    TransferHelper.safeTransfer(_lpToken, devaddr, liquidityFee);
    uint256 amountLocked = _amount.sub(liquidityFee);
    TokenLock memory token_lock;
    token_lock.lockDate = block.timestamp;
    token_lock.amount = amountLocked;
    token_lock.initialAmount = amountLocked;
    token_lock.unlockDate = _unlock_date;
    token_lock.lockID = tokenLocks[_lpToken].length;
    token_lock.owner = _withdrawer;
    // record the lock for the Pancakev2pair
    tokenLocks[_lpToken].push(token_lock);
    lockedTokens.Add(_lpToken);
    // record the lock for the user
    UserInfo storage user = users[_withdrawer];
    user.lockedTokens.Add(_lpToken);
    uint256[] storage user_locks = user.locksForToken[_lpToken];
    user_locks.push(token_lock.lockID);
    emit onDeposit(_lpToken, msg.sender, token_lock.amount, token_lock.lockDate, token_lock.unlockDate);
  }
  function relock (address _lpToken, uint256 _index, uint256 _lockID, uint256 _unlock_date) external nonReentrant {
    require(_unlock_date < 10000000000, 'TIMESTAMP INVALID'); // prevents errors when timestamp entered in milliseconds
    uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
    TokenLock storage userLock = tokenLocks[_lpToken][lockID];
    require(lockID == _lockID && userLock.owner == msg.sender, 'LOCK MISMATCH'); // ensures correct lock is affected
    require(userLock.unlockDate < _unlock_date, 'UNLOCK BEFORE');
    uint256 liquidityFee = userLock.amount.mul(gFees.liquidityFee).div(1000);
    uint256 amountLocked = userLock.amount.sub(liquidityFee);
    userLock.amount = amountLocked;
    userLock.unlockDate = _unlock_date;
    // send Pancakev2 fee to dev address
    TransferHelper.safeTransfer(_lpToken, devaddr, liquidityFee);
  }
  function withdraw (address _lpToken, uint256 _index, uint256 _lockID, uint256 _amount) external nonReentrant {
    require(_amount > 0, 'ZERO WITHDRAWL');
    uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
    TokenLock storage userLock = tokenLocks[_lpToken][lockID];
    require(lockID == _lockID && userLock.owner == msg.sender, 'LOCK MISMATCH'); // ensures correct lock is affected
    require(userLock.unlockDate < block.timestamp, 'NOT YET');
    userLock.amount = userLock.amount.sub(_amount);
    // clean user storage
    if (userLock.amount == 0) {
      uint256[] storage userLocks = users[msg.sender].locksForToken[_lpToken];
      userLocks[_index] = userLocks[userLocks.length-1];
      userLocks.pop();
      if (userLocks.length == 0) {
        users[msg.sender].lockedTokens.remove(_lpToken);
      }
    }
    TransferHelper.safeTransfer(_lpToken, msg.sender, _amount);
    emit onWithdraw(_lpToken, _amount);
  }
  function incrementLock (address _lpToken, uint256 _index, uint256 _lockID, uint256 _amount) external nonReentrant {
    require(_amount > 0, 'ZERO AMOUNT');
    uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
    TokenLock storage userLock = tokenLocks[_lpToken][lockID];
    require(lockID == _lockID && userLock.owner == msg.sender, 'LOCK MISMATCH'); // ensures correct lock is affected
    TransferHelper.safeTransferFrom(_lpToken, address(msg.sender), address(this), _amount);
    // send Pancakev2 fee to dev address
    uint256 liquidityFee = _amount.mul(gFees.liquidityFee).div(1000);
    TransferHelper.safeTransfer(_lpToken, devaddr, liquidityFee);
    uint256 amountLocked = _amount.sub(liquidityFee);
    userLock.amount = userLock.amount.add(amountLocked);
    emit onDeposit(_lpToken, msg.sender, amountLocked, userLock.lockDate, userLock.unlockDate);
  }
  function splitLock (address _lpToken, uint256 _index, uint256 _lockID, uint256 _amount) external payable nonReentrant {
    require(_amount > 0, 'ZERO AMOUNT');
    uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
    TokenLock storage userLock = tokenLocks[_lpToken][lockID];
    require(lockID == _lockID && userLock.owner == msg.sender, 'LOCK MISMATCH'); // ensures correct lock is affected
    require(msg.value == gFees.bnbFee, 'FEE NOT MET');
    devaddr.transfer(gFees.bnbFee);
    userLock.amount = userLock.amount.sub(_amount);
    TokenLock memory token_lock;
    token_lock.lockDate = userLock.lockDate;
    token_lock.amount = _amount;
    token_lock.initialAmount = _amount;
    token_lock.unlockDate = userLock.unlockDate;
    token_lock.lockID = tokenLocks[_lpToken].length;
    token_lock.owner = msg.sender;
    // record the lock for the Pancakev2pair
    tokenLocks[_lpToken].push(token_lock);
    // record the lock for the user
    UserInfo storage user = users[msg.sender];
    uint256[] storage user_locks = user.locksForToken[_lpToken];
    user_locks.push(token_lock.lockID);
  }
  function transferLockOwnership (address _lpToken, uint256 _index, uint256 _lockID, address payable _newOwner) external {
    require(msg.sender != _newOwner, 'OWNER');
    uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
    TokenLock storage transferredLock = tokenLocks[_lpToken][lockID];
    require(lockID == _lockID && transferredLock.owner == msg.sender, 'LOCK MISMATCH'); // ensures correct lock is affected
    // record the lock for the new Owner
    UserInfo storage user = users[_newOwner];
    user.lockedTokens.Add(_lpToken);
    uint256[] storage user_locks = user.locksForToken[_lpToken];
    user_locks.push(transferredLock.lockID);
    // remove the lock from the old owner
    uint256[] storage userLocks = users[msg.sender].locksForToken[_lpToken];
    userLocks[_index] = userLocks[userLocks.length-1];
    userLocks.pop();
    if (userLocks.length == 0) {
      users[msg.sender].lockedTokens.remove(_lpToken);
    }
    transferredLock.owner = _newOwner;
  }
  function migrate (address _lpToken, uint256 _index, uint256 _lockID, uint256 _amount) external nonReentrant {
    require(address(migrator) != address(0), "NOT SET");
    require(_amount > 0, 'ZERO MIGRATION');
    uint256 lockID = users[msg.sender].locksForToken[_lpToken][_index];
    TokenLock storage userLock = tokenLocks[_lpToken][lockID];
    require(lockID == _lockID && userLock.owner == msg.sender, 'LOCK MISMATCH'); // ensures correct lock is affected
    userLock.amount = userLock.amount.sub(_amount);
    // clean user storage
    if (userLock.amount == 0) {
      uint256[] storage userLocks = users[msg.sender].locksForToken[_lpToken];
      userLocks[_index] = userLocks[userLocks.length-1];
      userLocks.pop();
      if (userLocks.length == 0) {
        users[msg.sender].lockedTokens.remove(_lpToken);
      }
    } 
    TransferHelper.safeApprove(_lpToken, address(migrator), _amount);
    migrator.migrate(_lpToken, _amount, userLock.unlockDate, msg.sender);
  }
  function getNumLocksForToken (address _lpToken) external view returns (uint256) {
    return tokenLocks[_lpToken].length;
  }
  function getNumLockedTokens () external view returns (uint256) {
    return lockedTokens.length();
  }
  function getLockedTokenAtIndex (uint256 _index) external view returns (address) {
    return lockedTokens.at(_index);
  }
  // user functions
  function getUserNumLockedTokens (address _user) external view returns (uint256) {
    UserInfo storage user = users[_user];
    return user.lockedTokens.length();
  }
  function getUserLockedTokenAtIndex (address _user, uint256 _index) external view returns (address) {
    UserInfo storage user = users[_user];
    return user.lockedTokens.at(_index);
  }
  function getUserNumLocksForToken (address _user, address _lpToken) external view returns (uint256) {
    UserInfo storage user = users[_user];
    return user.locksForToken[_lpToken].length;
  }
  function getUserLockForTokenAtIndex (address _user, address _lpToken, uint256 _index) external view 
  returns (uint256, uint256, uint256, uint256, uint256, address) {
    uint256 lockID = users[_user].locksForToken[_lpToken][_index];
    TokenLock storage tokenLock = tokenLocks[_lpToken][lockID];
    return (tokenLock.lockDate, tokenLock.amount, tokenLock.initialAmount, tokenLock.unlockDate, tokenLock.lockID, tokenLock.owner);
  }
  // whitelist
  function getWhitelistedUsersLength () external view returns (uint256) {
    return feeWhitelist.length();
  }
  function getWhitelistedUserAtIndex (uint256 _index) external view returns (address) {
    return feeWhitelist.at(_index);
  }
  function getUserWhitelistStatus (address _user) external view returns (bool) {
    return feeWhitelist.contains(_user);
  }
}