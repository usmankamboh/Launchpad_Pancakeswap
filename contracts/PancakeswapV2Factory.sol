// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import "./PancakeswapExchange.sol";
import "./IPancakeswapExchange.sol";
contract PancakeswapV2Factory {
  event NewExchange(address indexed token, address indexed exchange);
  address public exchangeTemplate;
  uint256 public tokenCount;
  mapping (address => address) internal token_to_exchange;
  mapping (address => address) internal exchange_to_token;
  mapping (uint256 => address) internal id_to_token;
  function initializeFactory(address template) public {
    require(exchangeTemplate == address(0));
    require(template != address(0));
    exchangeTemplate = template;
  }
  function createExchange(address token) public returns (address) {
    require(token != address(0));
    require(exchangeTemplate != address(0));
    require(token_to_exchange[token] == address(0));
    PancakeswapExchange exchange = new PancakeswapExchange();
    exchange.setup(token);
    token_to_exchange[token] = address(exchange);
    exchange_to_token[address(exchange)] = token;
    uint256 token_id = tokenCount + 1;
    tokenCount = token_id;
    id_to_token[token_id] = token;
    emit NewExchange(token, address(exchange));
    return address(exchange);
  }
  function getExchange(address token) public view returns (address) {
    return token_to_exchange[token];
  }

  function getToken(address exchange) public view returns (address) {
    return exchange_to_token[exchange];
  }

  function getTokenWithId(uint256 token_id) public view returns (address) {
    return id_to_token[token_id];
  }

}

