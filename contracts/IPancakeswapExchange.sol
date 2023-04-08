// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
interface IPancakeswapExchange {
  event TokenPurchase(address indexed buyer, uint256 indexed bnb_sold, uint256 indexed tokens_bought);
  event BnbPurchase(address indexed buyer, uint256 indexed tokens_sold, uint256 indexed bnb_bought);
  event AddLiquidity(address indexed provider, uint256 indexed bnb_amount, uint256 indexed token_amount);
  event RemoveLiquidity(address indexed provider, uint256 indexed bnb_amount, uint256 indexed token_amount);
  function getInputPrice(uint256 input_amount, uint256 input_reserve, uint256 output_reserve) external view returns (uint256);
  function getOutputPrice(uint256 output_amount, uint256 input_reserve, uint256 output_reserve) external view returns (uint256);
  function bnbToTokenSwapInput(uint256 min_tokens, uint256 deadline) external payable returns (uint256);
  function bnbToTokenTransferInput(uint256 min_tokens, uint256 deadline, address recipient) external payable returns(uint256);
  function bnbToTokenSwapOutput(uint256 tokens_bought, uint256 deadline) external payable returns(uint256);
  function bnbToTokenTransferOutput(uint256 tokens_bought, uint256 deadline, address recipient) external payable returns (uint256);
  function tokenToBnbSwapInput(uint256 tokens_sold, uint256 min_bnb, uint256 deadline) external returns (uint256);
  function tokenToBnbTransferInput(uint256 tokens_sold, uint256 min_bnb, uint256 deadline, address recipient) external returns (uint256);
  function tokenToBnbSwapOutput(uint256 bnb_bought, uint256 max_tokens, uint256 deadline) external returns (uint256);
  function tokenToBnbTransferOutput(uint256 bnb_bought, uint256 max_tokens, uint256 deadline, address recipient) external returns (uint256);
  function tokenToTokenSwapInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address token_addr) 
    external returns (uint256);
  function tokenToTokenTransferInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address recipient, 
    address token_addr) 
    external returns (uint256);
  function tokenToTokenSwapOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address token_addr) 
    external returns (uint256);
  function tokenToTokenTransferOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address recipient, 
    address token_addr) 
    external returns (uint256);
  function tokenToExchangeSwapInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address exchange_addr) 
    external returns (uint256);
  function tokenToExchangeTransferInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address recipient, 
    address exchange_addr) 
    external returns (uint256);
  function tokenToExchangeSwapOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address exchange_addr) 
    external returns (uint256);
  function tokenToExchangeTransferOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address recipient, 
    address exchange_addr) 
    external returns (uint256);
  function getBnbToTokenInputPrice(uint256 bnb_sold) external view returns (uint256);
  function getBnbToTokenOutputPrice(uint256 tokens_bought) external view returns (uint256);
  function getTokenToBnbInputPrice(uint256 tokens_sold) external view returns (uint256);
  function getTokenToBnbOutputPrice(uint256 bnb_bought) external view returns (uint256);
  function tokenAddress() external view returns (address);
  function factoryAddress() external view returns (address);
  function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline) external payable returns (uint256);
  function removeLiquidity(uint256 amount, uint256 min_bnb, uint256 min_tokens, uint256 deadline) external returns (uint256, uint256);
}