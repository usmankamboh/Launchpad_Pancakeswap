// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import "./BEP20.sol";
import "./IBEP20.sol";
import "./IPancakeswapFactory.sol";
import "./IPancakeswapExchange.sol";
import "./SafeMath.sol";
  contract PancakeswapExchange {
  using SafeMath for uint256;
  // Variables
  bytes32 public name;         // Smart
  bytes32 public symbol;       // SSS
  uint256 public decimals;     // 18
  uint256 internal _totalSupply;
  mapping (address => uint256) internal _balances;
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
  IBEP20 token;                // address of the BEP20 token traded on this contract
  IPancakeswapFactory factory;     // interface for the factory that created this contract
  // Events
  event TokenPurchase(address indexed buyer, uint256 indexed bnb_sold, uint256 indexed tokens_bought);
  event BnbPurchase(address indexed buyer, uint256 indexed tokens_sold, uint256 indexed bnb_bought);
  event AddLiquidity(address indexed provider, uint256 indexed bnb_amount, uint256 indexed token_amount);
  event RemoveLiquidity(address indexed provider, uint256 indexed bnb_amount, uint256 indexed token_amount);
  function setup(address token_addr) public {
    require( 
      address(factory) == address(0) && address(token) == address(0) && token_addr != address(0), 
      "INVALID_ADDRESS"
    );
    factory = IPancakeswapFactory(msg.sender);
    token = IBEP20(token_addr);
    name = "";
    symbol ="";
    //decimals = 18;
  }
  function totalSupply() public view returns (uint256) {
    return _totalSupply;
  }
  function balanceOf(address owner) public view returns (uint256) {
    return _balances[owner];
  }
  function getInputPrice(uint256 input_amount, uint256 input_reserve, uint256 output_reserve) public pure returns (uint256) {
    require(input_reserve > 0 && output_reserve > 0, "INVALID_VALUE");
    uint256 input_amount_with_fee = input_amount.mul(997);
    uint256 numerator = input_amount_with_fee.mul(output_reserve);
    uint256 denominator = input_reserve.mul(1000).add(input_amount_with_fee);
    return numerator / denominator;
  }
  function getOutputPrice(uint256 output_amount, uint256 input_reserve, uint256 output_reserve) public pure returns (uint256) {
    require(input_reserve > 0 && output_reserve > 0);
    uint256 numerator = input_reserve.mul(output_amount).mul(1000);
    uint256 denominator = (output_reserve.sub(output_amount)).mul(997);
    return (numerator / denominator).add(1);
  }
  function bnbToTokenInput(uint256 bnb_sold, uint256 min_tokens, uint256 deadline, address buyer, address recipient) private returns (uint256) {
    require(deadline >= block.timestamp && min_tokens > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 tokens_bought = getInputPrice(bnb_sold, address(this).balance.sub(bnb_sold), token_reserve);
    require(tokens_bought >= min_tokens);
    require(token.transfer(recipient, tokens_bought));
    emit TokenPurchase(buyer, bnb_sold, tokens_bought);
    return tokens_bought;
  }
  function bnbToTokenSwapInput(uint256 min_tokens, uint256 deadline) public payable returns (uint256) {
    return bnbToTokenInput(msg.value, min_tokens, deadline, msg.sender, msg.sender);
  }
  function  bnbToTokenTransferInput(uint256 min_tokens, uint256 deadline, address recipient) public payable returns(uint256) {
    require(recipient != address(this) && recipient != address(0));
    return bnbToTokenInput(msg.value, min_tokens, deadline, msg.sender, recipient);
  }
  function bnbToTokenOutput(uint256 tokens_bought, uint256 max_bnb, uint256 deadline, address payable buyer, address recipient) private returns (uint256) {
    require(deadline >= block.timestamp && tokens_bought > 0 && max_bnb > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 bnb_sold = getOutputPrice(tokens_bought, address(this).balance.sub(max_bnb), token_reserve);
    // Throws if bnb_sold > max_bnb
    uint256 bnb_refund = max_bnb.sub(bnb_sold);
    if (bnb_refund > 0) {
      buyer.transfer(bnb_refund);
    }
    require(token.transfer(recipient, tokens_bought));
    emit TokenPurchase(buyer, bnb_sold, tokens_bought);
    return bnb_sold;
  }
  function bnbToTokenSwapOutput(uint256 tokens_bought, uint256 deadline) public payable returns(uint256) {
    return bnbToTokenOutput(tokens_bought, msg.value, deadline, payable (msg.sender), msg.sender);
  }
  function bnbToTokenTransferOutput(uint256 tokens_bought, uint256 deadline, address recipient) public payable returns (uint256) {
    require(recipient != address(this) && recipient != address(0));
    return bnbToTokenOutput(tokens_bought, msg.value, deadline, payable (msg.sender), recipient);
  }
  function tokenToBnbInput(uint256 tokens_sold, uint256 min_bnb, uint256 deadline, address buyer, address payable recipient) private returns (uint256) {
    require(deadline >= block.timestamp && tokens_sold > 0 && min_bnb > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 bnb_bought = getInputPrice(tokens_sold, token_reserve, address(this).balance);
    uint256 wei_bought = bnb_bought;
    require(wei_bought >= min_bnb);
    recipient.transfer(wei_bought);
    require(token.transferFrom(buyer, address(this), tokens_sold));
    emit BnbPurchase(buyer, tokens_sold, wei_bought);
    return wei_bought;
  }
  function tokenToBnbSwapInput(uint256 tokens_sold, uint256 min_bnb, uint256 deadline) public payable returns (uint256) {
    return tokenToBnbInput(tokens_sold, min_bnb, deadline, payable(msg.sender),payable(msg.sender));
  }
  function tokenToBnbTransferInput(uint256 tokens_sold, uint256 min_bnb, uint256 deadline, address payable recipient) public returns (uint256) {
    require(recipient != address(this) && recipient != address(0));
    return tokenToBnbInput(tokens_sold, min_bnb, deadline, msg.sender, recipient);
  }
  function tokenToBnbOutput(uint256 bnb_bought, uint256 max_tokens, uint256 deadline, address buyer, address payable recipient) private returns (uint256) {
    require(deadline >= block.timestamp && bnb_bought > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 tokens_sold = getOutputPrice(bnb_bought, token_reserve, address(this).balance);
    // tokens sold is always > 0
    require(max_tokens >= tokens_sold);
    recipient.transfer(bnb_bought);
    require(token.transferFrom(buyer, address(this), tokens_sold));
    emit BnbPurchase(buyer, tokens_sold, bnb_bought);
    return tokens_sold;
  }
  function tokenToBnbSwapOutput(uint256 bnb_bought, uint256 max_tokens, uint256 deadline) public returns (uint256) {
    return tokenToBnbOutput(bnb_bought, max_tokens, deadline, payable (msg.sender), payable (msg.sender));
  }
  function tokenToBnbTransferOutput(uint256 bnb_bought, uint256 max_tokens, uint256 deadline, address payable recipient) public returns (uint256) {
    require(recipient != address(this) && recipient != address(0));
    return tokenToBnbOutput(bnb_bought, max_tokens, deadline, msg.sender, recipient);
  }
  function tokenToTokenInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline,
    address buyer, 
    address recipient, 
    address payable exchange_addr) 
    private returns (uint256) 
  {
    require(deadline >= block.timestamp && tokens_sold > 0 && min_tokens_bought > 0 && min_bnb_bought > 0);
    require(exchange_addr != address(this) && exchange_addr != address(0));
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 bnb_bought = getInputPrice(tokens_sold, token_reserve, address(this).balance);
    uint256 wei_bought = bnb_bought;
    require(wei_bought >= min_bnb_bought);
    require(token.transferFrom(buyer, address(this), tokens_sold));
    uint256 tokens_bought = IPancakeswapExchange(exchange_addr).bnbToTokenTransferInput{value:wei_bought}(min_tokens_bought, deadline, recipient);
    emit BnbPurchase(buyer, tokens_sold, wei_bought);
    return tokens_bought;
  }
  function tokenToTokenSwapInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address token_addr) 
    public returns (uint256) 
  {
    address payable exchange_addr = factory.getExchange(token_addr);
    return tokenToTokenInput(tokens_sold, min_tokens_bought, min_bnb_bought, deadline, msg.sender, msg.sender, exchange_addr);
  }
  function tokenToTokenTransferInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address recipient, 
    address token_addr) 
    public returns (uint256) 
  {
    address payable exchange_addr = factory.getExchange(token_addr);
    return tokenToTokenInput(tokens_sold, min_tokens_bought, min_bnb_bought, deadline, msg.sender, recipient, exchange_addr);
  }
  function tokenToTokenOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address buyer, 
    address recipient, 
    address payable exchange_addr) 
    private returns (uint256) 
  {
    require(deadline >= block.timestamp && (tokens_bought > 0 && max_bnb_sold > 0));
    require(exchange_addr != address(this) && exchange_addr != address(0));
    uint256 bnb_bought = IPancakeswapExchange(exchange_addr).getBnbToTokenOutputPrice(tokens_bought);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 tokens_sold = getOutputPrice(bnb_bought, token_reserve, address(this).balance);
    // tokens sold is always > 0
    require(max_tokens_sold >= tokens_sold && max_bnb_sold >= bnb_bought);
    require(token.transferFrom(buyer, address(this), tokens_sold));
    uint256 bnb_sold = IPancakeswapExchange(exchange_addr).bnbToTokenTransferOutput{value:bnb_bought}(tokens_bought, deadline, recipient);
    emit BnbPurchase(buyer, tokens_sold, bnb_bought);
    return tokens_sold;
  }
  function tokenToTokenSwapOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address token_addr) 
    public returns (uint256) 
  {
    address payable exchange_addr = factory.getExchange(token_addr);
    return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_bnb_sold, deadline, msg.sender, msg.sender, exchange_addr);
  }
  function tokenToTokenTransferOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address recipient, 
    address token_addr) 
    public returns (uint256) 
  {
    address payable exchange_addr = factory.getExchange(token_addr);
    return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_bnb_sold, deadline, msg.sender, recipient, exchange_addr);
  }
  function tokenToExchangeSwapInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address payable exchange_addr) 
    public returns (uint256) 
  {
    return tokenToTokenInput(tokens_sold, min_tokens_bought, min_bnb_bought, deadline, msg.sender, msg.sender, exchange_addr);
  }
  function tokenToExchangeTransferInput(
    uint256 tokens_sold, 
    uint256 min_tokens_bought, 
    uint256 min_bnb_bought, 
    uint256 deadline, 
    address recipient, 
    address payable exchange_addr) 
    public returns (uint256) 
  {
    require(recipient != address(this));
    return tokenToTokenInput(tokens_sold, min_tokens_bought, min_bnb_bought, deadline, msg.sender, recipient, exchange_addr);
  }
  function tokenToExchangeSwapOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address payable exchange_addr) 
    public returns (uint256) 
  {
    return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_bnb_sold, deadline, msg.sender, msg.sender, exchange_addr);
  }
  function tokenToExchangeTransferOutput(
    uint256 tokens_bought, 
    uint256 max_tokens_sold, 
    uint256 max_bnb_sold, 
    uint256 deadline, 
    address recipient, 
    address payable exchange_addr) 
    public returns (uint256) 
  {
    require(recipient != address(this));
    return tokenToTokenOutput(tokens_bought, max_tokens_sold, max_bnb_sold, deadline, msg.sender, recipient, exchange_addr);
  }
  function getBnbToTokenInputPrice(uint256 bnb_sold) public view returns (uint256) {
   // require(bnb_sold > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    return getInputPrice(bnb_sold, address(this).balance, token_reserve);
  }
  function getBnbToTokenOutputPrice(uint256 tokens_bought) public view returns (uint256) {
    require(tokens_bought > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 bnb_sold = getOutputPrice(tokens_bought, address(this).balance, token_reserve);
    return bnb_sold;
  }
  function getTokenToBnbInputPrice(uint256 tokens_sold) public view returns (uint256) {
    require(tokens_sold > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 bnb_bought = getInputPrice(tokens_sold, token_reserve, address(this).balance);
    return bnb_bought;
  }
  function getTokenToBnbOutputPrice(uint256 bnb_bought) public view returns (uint256) {
    require(bnb_bought > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    return getOutputPrice(bnb_bought, token_reserve, address(this).balance);
  }
  function tokenAddress() public view returns (address) {
    return address(token);
  }
  function factoryAddress() public view returns (address) {
    return address(factory);
  }
  function addLiquidity(uint256 min_liquidity, uint256 max_tokens, uint256 deadline) public payable returns (uint256) {
    require(deadline > block.timestamp && max_tokens > 0 && msg.value > 0, 'PANCAKEswapExchange#addLiquidity: INVALID_ARGUMENT');
    uint256 total_liquidity = _totalSupply;
    if (total_liquidity > 0) {
      require(min_liquidity > 0);
      uint256 bnb_reserve = address(this).balance.sub(msg.value);
      uint256 token_reserve = token.balanceOf(address(this));
      uint256 token_amount = (msg.value.mul(token_reserve) / bnb_reserve).add(1);
      uint256 liquidity_minted = msg.value.mul(total_liquidity) / bnb_reserve;
      require(max_tokens >= token_amount && liquidity_minted >= min_liquidity);
      _balances[msg.sender] = _balances[msg.sender].add(liquidity_minted);
      _totalSupply = total_liquidity.add(liquidity_minted);
      require(token.transferFrom(msg.sender, address(this), token_amount));
      emit AddLiquidity(msg.sender, msg.value, token_amount);
      emit Transfer(address(0), msg.sender, liquidity_minted);
      return liquidity_minted;
    } else {
      require(address(factory) != address(0) && address(token) != address(0) && msg.value >= 1000000000, "INVALID_VALUE");
      require(factory.getExchange(address(token)) == address(this));
      uint256 token_amount = max_tokens;
      uint256 initial_liquidity = address(this).balance;
      _totalSupply = initial_liquidity;
      _balances[msg.sender] = initial_liquidity;
      require(token.transferFrom(msg.sender, address(this), token_amount));
      emit AddLiquidity(msg.sender, msg.value, token_amount);
      emit Transfer(address(0), msg.sender, initial_liquidity);
      return initial_liquidity;
    }
  }
  function removeLiquidity(uint256 amount, uint256 min_bnb, uint256 min_tokens, uint256 deadline) public returns (uint256, uint256) {
    require(amount > 0 && deadline > block.timestamp && min_bnb > 0 && min_tokens > 0);
    uint256 total_liquidity = _totalSupply;
    require(total_liquidity > 0);
    uint256 token_reserve = token.balanceOf(address(this));
    uint256 bnb_amount = amount.mul(address(this).balance) / total_liquidity;
    uint256 token_amount = amount.mul(token_reserve) / total_liquidity;
    require(bnb_amount >= min_bnb && token_amount >= min_tokens);
    _balances[msg.sender] = _balances[msg.sender].sub(amount);
    _totalSupply = total_liquidity.sub(amount);
    payable(msg.sender).transfer(bnb_amount);
    require(token.transfer(msg.sender, token_amount));
    emit RemoveLiquidity(msg.sender, bnb_amount, token_amount);
    emit Transfer(msg.sender, address(0), amount);
    return (bnb_amount, token_amount);
  }
}
