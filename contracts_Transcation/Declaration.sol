// SPDX-License-Identifier: --GRISE--

import "./Context.sol";
import "./Events.sol";

pragma solidity =0.7.6;

abstract contract Declaration is Context, Events {

    uint256 constant _decimals = 18;
    uint256 constant REI_PER_GRISE = 10 ** _decimals;

    uint32 constant SECONDS_IN_DAY = 24 hours;//86400 seconds; // 24 hours
    uint32 constant SECONDS_IN_DAY_LP = 4 hours; // 4 hours
    uint32 constant GRISE_WEEK = 7;
    uint32 constant GRISE_MONTH = 4 * GRISE_WEEK;
    uint32 constant GRISE_YEAR = 12 * GRISE_MONTH;

    uint64 constant PRECISION_RATE = 1E18;
    uint16 constant REWARD_PRECISION_RATE = 1E4;
    uint256 immutable LAUNCH_TIME;
    uint256 immutable LP_LAUNCH_TIME; // PreSale Launch Time
    
    uint16 constant SELL_TRANS_FEE = 347; // 3.47% multiple 1E4 Precision
    uint16 constant TRANSC_RESERVOIR_REWARD = 3115;
    uint16 constant TRANSC_STAKER_REWARD = 1633;
    uint16 constant TRANSC_TOKEN_HOLDER_REWARD = 2612;
    uint16 constant TEAM_SELL_TRANSC_REWARD = 1431;
    uint16 constant SELL_TRANS_BURN = 1209;
    
    uint16 constant BUY_TRANS_FEE = 30; // .30 multiple 1E4 Precision
    uint16 constant TEAM_BUY_TRANS_REWARD = 1667; // 16.67 multiple 1E2 Precisions
    uint16 constant BUY_TRANS_BURN = 8333;
    address constant TEAM_ADDRESS = 0xa377433831E83C7a4Fa10fB75C33217cD7CABec2;
    address constant DEVELOPER_ADDRESS = 0x7FF1F8C467114BfBbCC56E406c0Ec21E781bB959;
    
    constructor() {
        // Temperary set as current block timestamp 
        LAUNCH_TIME = block.timestamp;//1604966400; // (10th November 2020 @00:00 GMT == day 0)
        LP_LAUNCH_TIME = block.timestamp;
    }


    uint256 internal stakedToken;
    uint256 internal mediumTermShares;
    mapping(uint256 => uint256) internal sellTranscFee;  // week ==> weekly Accumalted transc fee
    mapping(uint256 => uint256) internal reservoirRewardPerShare;
    mapping(uint256 => uint256) internal stakerRewardPerShare;
    mapping(uint256 => uint256) internal tokenHolderReward;
    mapping(address => mapping(uint256 => bool)) internal isTranscFeeClaimed;
    mapping(uint256 => uint256) internal totalToken;
    mapping(address => uint16) internal staker;
}