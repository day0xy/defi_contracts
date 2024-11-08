pragma solidity >=0.5.0;

// 该函数将流动性从 Uniswap V1 迁移到 Uniswap V2
interface IUniswapV2Migrator {
    function migrate(address token, uint amountTokenMin, uint amountETHMin, address to, uint deadline) external;
}
