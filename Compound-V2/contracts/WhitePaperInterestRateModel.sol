// SPDX-License-Identifier: BSD-3-Clause
pragma solidity ^0.8.10;

import "./InterestRateModel.sol";

/**
  * @title Compound's WhitePaperInterestRateModel Contract
  * @author Compound
  * @notice The parameterized model described in section 2.4 of the original Compound Protocol whitepaper
  */
contract WhitePaperInterestRateModel is InterestRateModel {
    event NewInterestParams(uint baseRatePerBlock, uint multiplierPerBlock);

    uint256 private constant BASE = 1e18;

    /**
     * @notice The approximate number of blocks per year that is assumed by the interest rate model
     */
    uint public constant blocksPerYear = 2102400;

    /**
     * @notice The multiplier of utilization rate that gives the slope of the interest rate
     */
    uint public multiplierPerBlock;

    /**
     * @notice The base interest rate which is the y-intercept when utilization rate is 0
     */
    uint public baseRatePerBlock;

    /**
     * @notice Construct an interest rate model
     * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by BASE)
     * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by BASE)
     */
    constructor(uint baseRatePerYear, uint multiplierPerYear) public {
        baseRatePerBlock = baseRatePerYear / blocksPerYear;
        multiplierPerBlock = multiplierPerYear / blocksPerYear;

        emit NewInterestParams(baseRatePerBlock, multiplierPerBlock);
    }

    /**
     * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market (currently unused)
     * @return The utilization rate as a mantissa between [0, BASE]
     */
    //利用率
    function utilizationRate(uint cash, uint borrows, uint reserves) public pure returns (uint) {
        // Utilization rate is 0 when there are no borrows
        if (borrows == 0) {
            return 0;
        }

        //借出去的钱*BASE/(现金+借出去的钱-储备)
        //储备，这一部分钱不能借出去
        return borrows * BASE / (cash + borrows - reserves);
    }

    /**
     * @notice Calculates the current borrow rate per block, with the error code expected by the market
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @return The borrow rate percentage per block as a mantissa (scaled by BASE)
     */
    //计算借款利率
    function getBorrowRate(uint cash, uint borrows, uint reserves) override public view returns (uint) {
        //
        uint ur = utilizationRate(cash, borrows, reserves);
        //（利用率*每个块的利率增长率）/BASE+每个块的基础利率
        return (ur * multiplierPerBlock / BASE) + baseRatePerBlock;
    }

    /**
     * @notice Calculates the current supply rate per block
     * @param cash The amount of cash in the market
     * @param borrows The amount of borrows in the market
     * @param reserves The amount of reserves in the market
     * @param reserveFactorMantissa The current reserve factor for the market
     * @return The supply rate percentage per block as a mantissa (scaled by BASE)
     */
    //计算存款利率
    function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) override public view returns (uint) {
        //ReserveFactor是储备利率，平台要将一部分利息收入，作为储备金存起来，应对市场波动风险
        //储备因子是一个比例，决定了有多少利息中有多少部分被分配给储备金


        //1-储备因子，用于计算实际分配给资金池的利率
        uint oneMinusReserveFactor = BASE - reserveFactorMantissa;
        //获取借款利率
        uint borrowRate = getBorrowRate(cash, borrows, reserves);
        //分配给资金池的利率 = 借款利率*（1-储备因子）/BASE
        uint rateToPool = borrowRate * oneMinusReserveFactor / BASE;
        //返回存款利率 = 利用率 * 分配给资金池的利率 / BASE
        return utilizationRate(cash, borrows, reserves) * rateToPool / BASE;
    }
}
