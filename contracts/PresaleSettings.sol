// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12; 
import "./Ownable.sol";
import "./EnumerableSet.sol";
import "./IBEP20.sol";
contract PresaleSettings is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private EARLY_ACCESS_TOKENS;
    mapping(address => uint256) public EARLY_ACCESS_MAP;
    EnumerableSet.AddressSet private ALLOWED_REFERRERS;
    struct Settings {
        uint256 BASE_FEE; // base fee divided by 1000
        uint256 TOKEN_FEE; // token fee divided by 1000
        uint256 REFERRAL_FEE; // a referrals percentage of the presale profits divided by 1000
        address payable BNB_FEE_ADDRESS;
        address payable TOKEN_FEE_ADDRESS;
        uint256 BNB_CREATION_FEE; // fee to generate a presale contract on the platform
        uint256 ROUND1_LENGTH; // length of round 1 in blocks
        uint256 MAX_PRESALE_LENGTH; // maximum difference between start and endblock
    }
    Settings public SETTINGS;
    constructor() public {
        SETTINGS.BASE_FEE = 0; // 0%
        SETTINGS.TOKEN_FEE = 0; // 0%
        SETTINGS.REFERRAL_FEE = 0; // 0%
        SETTINGS.BNB_CREATION_FEE =0;//5e17
        SETTINGS.BNB_FEE_ADDRESS = payable (msg.sender);
        SETTINGS.TOKEN_FEE_ADDRESS = payable(msg.sender);
        SETTINGS.ROUND1_LENGTH = 0; // 553 blocks = 2 hours
        SETTINGS.MAX_PRESALE_LENGTH = 0; //120960 14days
    }
    function getRound1Length () external view returns (uint256) {
        return SETTINGS.ROUND1_LENGTH;
    }
    function getMaxPresaleLength () external view returns (uint256) {
        return SETTINGS.MAX_PRESALE_LENGTH;
    }
    function getBaseFee () external view returns (uint256) {
        return SETTINGS.BASE_FEE;
    }
    function getTokenFee () external view returns (uint256) {
        return SETTINGS.TOKEN_FEE;
    }
    function getReferralFee () external view returns (uint256) {
        return SETTINGS.REFERRAL_FEE;
    }
    function getBnbCreationFee () external view returns (uint256) {
        return SETTINGS.BNB_CREATION_FEE;
    }
    function getBnbAddress () external view returns (address payable) {
        return SETTINGS.BNB_FEE_ADDRESS;
    }
    function getTokenAddress () external view returns (address payable) {
        return SETTINGS.TOKEN_FEE_ADDRESS;
    }
    function setFeeAddresses(address payable _bnbAddress, address payable _tokenFeeAddress) external onlyOwner {
        SETTINGS.BNB_FEE_ADDRESS = _bnbAddress;
        SETTINGS.TOKEN_FEE_ADDRESS = _tokenFeeAddress;
    }
    function setFees(uint256 _baseFee, uint256 _tokenFee, uint256 _bnbCreationFee, uint256 _referralFee) external onlyOwner {
        SETTINGS.BASE_FEE = _baseFee;
        SETTINGS.TOKEN_FEE = _tokenFee;
        SETTINGS.REFERRAL_FEE = _referralFee;
        SETTINGS.BNB_CREATION_FEE = _bnbCreationFee;
    }
    function setRound1Length(uint256 _round1Length) external onlyOwner {
        SETTINGS.ROUND1_LENGTH = _round1Length;
    }
    function setMaxPresaleLength(uint256 _maxLength) external onlyOwner {
        SETTINGS.MAX_PRESALE_LENGTH = _maxLength;
    }
    function editAllowedReferrers(address payable _referrer, bool _allow) external onlyOwner {
        if (_allow) {
            ALLOWED_REFERRERS.Add(_referrer);
        } else {
            ALLOWED_REFERRERS.remove(_referrer);
        }
    }
    function editEarlyAccessTokens(address _token, uint256 _holdAmount, bool _allow) external onlyOwner {
        if (_allow) {
            EARLY_ACCESS_TOKENS.Add(_token);
        } else {
            EARLY_ACCESS_TOKENS.remove(_token);
        }
        EARLY_ACCESS_MAP[_token] = _holdAmount;
    }
    function userHoldsSufficientRound1Token (address _user) external view returns (bool) {
        if (earlyAccessTokensLength() == 0) {
            return true;
        }
        for (uint i = 0; i < earlyAccessTokensLength(); i++) {
          (address token, uint256 amountHold) = getEarlyAccessTokenAtIndex(i);
          if (IBEP20(token).balanceOf(_user) >= amountHold) {
              return true;
          }
        }
        return false;
    }
    function getEarlyAccessTokenAtIndex(uint256 _index) public view returns (address, uint256) {
        address tokenAddress = EARLY_ACCESS_TOKENS.at(_index);
        return (tokenAddress, EARLY_ACCESS_MAP[tokenAddress]);
    }
    function earlyAccessTokensLength() public view returns (uint256) {
        return EARLY_ACCESS_TOKENS.length();
    }
    // Referrers
    function allowedReferrersLength() external view returns (uint256) {
        return ALLOWED_REFERRERS.length();
    }
    function getReferrerAtIndex(uint256 _index) external view returns (address) {
        return ALLOWED_REFERRERS.at(_index);
    }
    function referrerIsValid(address _referrer) external view returns (bool) {
        return ALLOWED_REFERRERS.contains(_referrer);
    }   
}