// SPDX-License-Identifier: --🦉--

import "./Context.sol";
import "./Events.sol";

pragma solidity =0.7.6;

interface ERC20TokenI {

    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )  external returns (
        bool success
    );

    function approve(
        address _spender,
        uint256 _value
    )  external returns (
        bool successs
    );
}

abstract contract Declaration is Context, Events {

    uint256 constant _decimals = 18;
    uint256 constant YODAS_PER_GRISE = 10 ** _decimals;

    uint32 constant SECONDS_IN_DAY = 86400 seconds; // 24 hours
    uint32 constant SECONDS_IN_DAY_LP = 240 seconds; // 4 hours
    uint32 constant GRISE_WEEK = 7;
    uint32 constant GRISE_MONTH = 4 * GRISE_WEEK;
    uint32 constant GRISE_YEAR = 12 * GRISE_MONTH;

    uint64 constant PRECISION_RATE = 1E18;
    uint16 constant REWARD_PRECISION_RATE = 1E4;
    uint256 immutable LAUNCH_TIME;
    
    uint16 constant SELL_TRANS_FEE = 347; // 3.47% multiple 1E4 Precision
    uint16 constant TRANSC_RESERVOIR_REWARD = 3115;
    uint16 constant TRANSC_STAKER_REWARD = 1633;
    uint16 constant TRANSC_TOKEN_HOLDER_REWARD = 2612;
    uint16 constant TEAM_SELL_TRANSC_REWARD = 1431;
    uint16 constant SELL_TRANS_BURN = 1209;
    
    uint16 constant BUY_TRANS_FEE = 30; // .30 multiple 1E2 Precision
    uint16 constant TEAM_BUY_TRANS_REWARD = 1667; // 16.67 multiple 1E2 Precisions
    uint16 constant BUY_TRANS_BURN = 8333;
    address constant TEAM_ADDRESS = 0x7FF1F8C467114BfBbCC56E406c0Ec21E781bB959; // My Address

    uint256 constant TEMP_PRECISION = 1E18;
    
    constructor() {
        LAUNCH_TIME = 1604966400; // (10th November 2020 @00:00 GMT == day 0)
    }


    uint256 internal stakedToken;
    uint256 internal mediumTermShares;
    mapping(uint256 => uint256) public sellTranscFee;  // week ==> weekly Accumalted transc fee
    mapping(uint256 => uint256) internal reservoirRewardPerShare;
    mapping(uint256 => uint256) internal stakerRewardPerShare;
    mapping(uint256 => uint256) internal tokenHolderReward;
    mapping(address => mapping(uint256 => bool)) internal isTranscFeeClaimed;
    mapping(uint256 => uint256) internal totalToken;
    mapping(address => bool) public isStaker;
}