pragma solidity =0.5.16;

import "./interfaces/IUniswapV2Pair.sol";
import "./UniswapV2ERC20.sol";
import "./libraries/Math.sol";
import "./libraries/UQ112x112.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Callee.sol";

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10 ** 3;
    bytes4 private constant SELECTOR =
        bytes4(keccak256(bytes("transfer(address,uint256)")));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0; // uses single storage slot, accessible via getReserves
    uint112 private reserve1; // uses single storage slot, accessible via getReserves
    uint32 private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, "UniswapV2: LOCKED");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    function getReserves()
        public
        view
        returns (
            uint112 _reserve0,
            uint112 _reserve1,
            uint32 _blockTimestampLast
        )
    {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(SELECTOR, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "UniswapV2: TRANSFER_FAILED"
        );
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(
        address indexed sender,
        uint amount0,
        uint amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    constructor() public {
        factory = msg.sender;
    }

    //初始化pair合约里的两个token地址，这是在factory合约里中调用的
    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, "UniswapV2: FORBIDDEN"); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(
        uint balance0,
        uint balance1,
        uint112 _reserve0,
        uint112 _reserve1
    ) private {
        //检查是否溢出2^122-1
        require(
            balance0 <= uint112(-1) && balance1 <= uint112(-1),
            "UniswapV2: OVERFLOW"
        );
        // 确保时间戳在32位整数内
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        //经过的时间
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        //price0 = reserve1 / reserve0
        //price1 = reserve0 / reserve1
        //price0CumulativeLast = price0 * timeElapsed + price0CumulativeLast
        //price1CumulativeLast = price1 * timeElapsed + price1CumulativeLast
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast +=
                uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) *
                timeElapsed;
            price1CumulativeLast +=
                uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) *
                timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(
        uint112 _reserve0,
        uint112 _reserve1
    ) private returns (bool feeOn) {
        address feeTo = IUniswapV2Factory(factory).feeTo();
        feeOn = feeTo != address(0);
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                uint rootKLast = Math.sqrt(_kLast);
                if (rootK > rootKLast) {
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        uint balance0 = IERC20(token0).balanceOf(address(this));
        uint balance1 = IERC20(token1).balanceOf(address(this));

        //添加的token数量为balance - reserve
        //amount0 = balance0 - _reserve0
        uint amount0 = balance0.sub(_reserve0);
        //amount1= balance1 - _reserve1
        uint amount1 = balance1.sub(_reserve1);

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            //初次创建币对，流动性为sqrt(amount0 * amount1) - 1000
            //liqiudity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);

            //向空地址铸造流动性代币，永久锁定第一个MINIMUM_LIQUIDITY个代币
            _mint(address(0), MINIMUM_LIQUIDITY); // permanently lock the first MINIMUM_LIQUIDITY tokens
        } else {
            //如果不是初次提供流动性，流动性为两者之间最小的那一个
            //amount0 * _totalSupply / _reserve0      ,  amount1 * _totalSupply / _reserve1
            liquidity = Math.min(
                amount0.mul(_totalSupply) / _reserve0,
                amount1.mul(_totalSupply) / _reserve1
            );
        }

        require(liquidity > 0, "UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED");
        //铸造流动性代币给用户
        _mint(to, liquidity);

        _update(balance0, balance1, _reserve0, _reserve1);
        //reserver0 * reserve1
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(
        address to
    ) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        //查看pair合约里的token0和token1的余额
        uint balance0 = IERC20(_token0).balanceOf(address(this));
        uint balance1 = IERC20(_token1).balanceOf(address(this));
        //router合约里 removeLiquidity会把流动性代币转移到pair合约里
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee

        //按照流动性代币占比来确定用户应得的token数量
        //amount0 = liquidity / _totalSupply * balance0
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution

        //按照流动性代币占比来确定用户应得的token数量
        //amount1 = liquidity / _totalSupply * balance1
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(
            amount0 > 0 && amount1 > 0,
            "UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED"
        );

        _burn(address(this), liquidity);
        //销毁流动性，用户要取出他的token
        //转移token到用户

        //按照流动性占比计算amount0和amount1，取出用户应得的token
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);

        // 更新流动性池子的余额
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));

        //内部的_update函数
        _update(balance0, balance1, _reserve0, _reserve1);
        //如果手续费开启，更新kLast
        if (feeOn) kLast = uint(reserve0).mul(reserve1); // reserve0 and reserve1 are up-to-date
        emit Burn(msg.sender, amount0, amount1, to);
    }

    // this low-level function should be called from a contract which performs important safety checks function swap(
        uint amount0Out,
        uint amount1Out,
        address to,
        bytes calldata data
    ) external lock {
        require(
            amount0Out > 0 || amount1Out > 0,
            "UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT"
        );

        //避免多次读取变量。节省gas
        //局部变量存储在 EVM 的堆栈中
        (uint112 _reserve0, uint112 _reserve1, ) = getReserves(); // gas savings
        require(
            amount0Out < _reserve0 && amount1Out < _reserve1,
            "UniswapV2: INSUFFICIENT_LIQUIDITY"
        );

        uint balance0;
        uint balance1;

        {
            //花括号的作用
            //限制作用域，防止堆栈太深导致错误
            // scope for _token{0,1}, avoids stack too deep errors

            address _token0 = token0;
            address _token1 = token1;
            require(to != _token0 && to != _token1, "UniswapV2: INVALID_TO");
            if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
            if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
            if (data.length > 0)
                IUniswapV2Callee(to).uniswapV2Call(
                    msg.sender,
                    amount0Out,
                    amount1Out,
                    data
                );
            //查看当前地址的token0的balance
            balance0 = IERC20(_token0).balanceOf(address(this));
            //查看当前地址的token1的balance
            balance1 = IERC20(_token1).balanceOf(address(this));
        }

        //balance0 = _reverse0 + (amount0In - amount0Out)
        //balance1 = _reverse1 + (amount1In - amount1Out)

        //所以 amount0In = balance0 - _reverse0 + amount0Out
        //所以 amount1In = balance1 - _reverse1 + amount1Out

        //如果balance0 > _reserve0 - amount0Out，那么amount0In = balance0 - (_reserve0 - amount0Out) 否则 amount0In = 0
        uint amount0In = balance0 > _reserve0 - amount0Out
            ? balance0 - (_reserve0 - amount0Out)
            : 0;

        //如果balance1 > _reserve1 - amount1Out，那么amount1In = balance1 - (_reserve1 - amount1Out) 否则 amount1In = 0

        uint amount1In = balance1 > _reserve1 - amount1Out
            ? balance1 - (_reserve1 - amount1Out)
            : 0;

        require(
            amount0In > 0 || amount1In > 0,
            "UniswapV2: INSUFFICIENT_INPUT_AMOUNT"
        );

        {
            // scope for reserve{0,1}Adjusted, avoids stack too deep errors

            //因为手续费是千三，所以这里放大1000倍
            //减去三是为了扣除0.3%的手续费

            //balance0Adjusted = balance0 * 1000 - amount0In * 3
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));

            //balance1Adjusted = balance1 * 1000 - amount1In * 3
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));

            // 2次方
            // 这行代码确保调整后的余额乘积大于或等于交易前的储备量乘积乘以 1000**2。
            // 乘以 1000**2 是为了将储备量放大，以便与调整后的余额进行比较。
            // 如果不满足这个条件，交易将被拒绝，并抛出 'UniswapV2: K' 错误。

            //require(balance0Adjusted * balance1Adjusted >= _reserve0 * _reserve1 * 1000**2)
            require(
                balance0Adjusted.mul(balance1Adjusted) >=
                    uint(_reserve0).mul(_reserve1).mul(1000 ** 2),
                "UniswapV2: K"
            );
        }

        //更新balance和reserve
        //更新合约里的时间戳和储备量，更新累计价格，计算TWAP，time-weighted average price
        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(
            _token0,
            to,
            IERC20(_token0).balanceOf(address(this)).sub(reserve0)
        );
        _safeTransfer(
            _token1,
            to,
            IERC20(_token1).balanceOf(address(this)).sub(reserve1)
        );
    }

    // force reserves to match balances
    function sync() external lock {
        _update(
            IERC20(token0).balanceOf(address(this)),
            IERC20(token1).balanceOf(address(this)),
            reserve0,
            reserve1
        );
    }
}
