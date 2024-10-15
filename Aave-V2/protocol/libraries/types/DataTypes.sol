// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.6.12;

library DataTypes {
  // refer to the whitepaper, section 1.1 basic concepts for a formal description of these properties.
  struct ReserveData {
    //stores the reserve configuration
    ReserveConfigurationMap configuration;


    //the liquidity index. Expressed in ray
    ///根据加权利率计算复利的索引序列
    uint128 liquidityIndex;
    //variable borrow index. Expressed in ray
    //根据浮动利率计算复利的索引序列
    uint128 variableBorrowIndex;


    //the current supply rate. Expressed in ray
    //加权了固定利率和浮动利率之后的当前利率
    uint128 currentLiquidityRate;
    //the current variable borrow rate. Expressed in ray
    //当前的浮动利率
    uint128 currentVariableBorrowRate;
    //the current stable borrow rate. Expressed in ray
    //当前的固定利率
    uint128 currentStableBorrowRate;


    uint40 lastUpdateTimestamp;

    //tokens addresses

    //aToken地址
    address aTokenAddress;
    //固定利率借贷token地址
    address stableDebtTokenAddress;
    //浮动利率借贷token地址
    address variableDebtTokenAddress;
    //address of the interest rate strategy
    //利率模型合约地址
    address interestRateStrategyAddress;


    //the id of the reserve. Represents the position in the list of the active reserves
    uint8 id;
  }

  //存储池配置位图
  struct ReserveConfigurationMap {
    //bit 0-15: LTV
    //bit 16-31: Liq. threshold
    //bit 32-47: Liq. bonus
    //bit 48-55: Decimals
    //bit 56: Reserve is active
    //bit 57: reserve is frozen
    //bit 58: borrowing is enabled
    //bit 59: stable rate borrowing enabled
    //bit 60-63: reserved
    //bit 64-79: reserve factor
    uint256 data;
  }

  struct UserConfigurationMap {
    uint256 data;
  }

  enum InterestRateMode {NONE, STABLE, VARIABLE}
}
