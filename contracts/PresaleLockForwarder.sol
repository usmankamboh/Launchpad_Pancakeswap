// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;
import "./Ownable.sol";
import "./TransferHelper.sol";
import "./IBEP20.sol";
import "./Context.sol";
interface IPresaleFactory {
    function registerPresale (address _presaleAddress) external;
    function presaleIsRegistered(address _presaleAddress) external view returns (bool);
}
interface IPancakeswapV2Locker {
    function lockLPToken (address _lpToken, uint256 _amount, uint256 _unlock_date, address payable _referral, bool _fee_in_bnb, address payable _withdrawer) external payable;
}
interface IPancakeswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
interface IPancakeswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);
    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);
    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
    function initialize(address, address) external;
}
contract PresaleLockForwarder is Ownable {
    IPresaleFactory public PRESALE_FACTORY;
    IPancakeswapV2Locker public SMART_LOCKER;
    IPancakeswapV2Factory public PancakeswapV2_FACTORY;
    constructor(IPresaleFactory _PRESALE_FACTORY,IPancakeswapV2Locker _SMART_LOCKER,IPancakeswapV2Factory _PancakeswapV2_FACTORY ) public{
        PRESALE_FACTORY = _PRESALE_FACTORY;
        SMART_LOCKER = _SMART_LOCKER;
        PancakeswapV2_FACTORY = _PancakeswapV2_FACTORY;
    }
    function PancakeswapPairIsInitialised (address _token0, address _token1) public view returns (bool) {
        address pairAddress = PancakeswapV2_FACTORY.getPair(_token0, _token1);
        if (pairAddress == address(0)) {
            return false;
        }
        uint256 balance = IBEP20(_token0).balanceOf(pairAddress);
        if (balance > 0) {
            return true;
        }
        return false;
    }
    function lockLiquidity (IBEP20 _baseToken, IBEP20 _saleToken, uint256 _baseAmount, uint256 _saleAmount, uint256 _unlock_date, address payable _withdrawer) external {
        require(PRESALE_FACTORY.presaleIsRegistered(msg.sender), 'PRESALE NOT REGISTERED');
        address pair = PancakeswapV2_FACTORY.getPair(address(_baseToken), address(_saleToken));
        if (pair == address(0)) {
            PancakeswapV2_FACTORY.createPair(address(_baseToken), address(_saleToken));
            pair = PancakeswapV2_FACTORY.getPair(address(_baseToken), address(_saleToken));
        }
        TransferHelper.safeTransferFrom(address(_baseToken), msg.sender, address(pair), _baseAmount);
        TransferHelper.safeTransferFrom(address(_saleToken), msg.sender, address(pair), _saleAmount);
        IPancakeswapV2Pair(pair).mint(address(this));
        uint256 totalLPTokensMinted = IPancakeswapV2Pair(pair).balanceOf(address(this));
        require(totalLPTokensMinted != 0 , "LP creation failed");
        TransferHelper.safeApprove(pair, address(SMART_LOCKER), totalLPTokensMinted);
        uint256 unlock_date = _unlock_date > 9999999999 ? 9999999999 : _unlock_date;
        SMART_LOCKER.lockLPToken(pair, totalLPTokensMinted, unlock_date, payable (address(0)), true, _withdrawer);
    }
    
}