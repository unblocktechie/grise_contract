// SPDX-License-Identifier: --🦉--

pragma solidity =0.7.6;

import "./Global.sol";

abstract contract Declaration is Global {

    uint256 constant _decimals = 18;
    uint256 constant REI_PER_GRISE = 10 ** _decimals; // 1 GRISE = 1E18 REI
    
    uint64 constant PRECISION_RATE = 1E18;
    uint32 constant REWARD_PRECISION_RATE = 1E4;

    uint16 constant GRISE_WEEK = 7;
    uint16 constant GRISE_MONTH = GRISE_WEEK * 4;
    uint16 constant GRISE_YEAR = GRISE_MONTH * 12;

    // Inflation Reward
    uint32 constant INFLATION_RATE = 57658685; // per day Inflation Amount
    uint16 constant MED_TERM_INFLATION_REWARD = 3000; // 30% of Inflation Amount with 1E4 Precision
    uint16 constant LONG_TERM_INFLATION_REWARD = 7000; // 70% of Inflation Amount with 1E4 Precision

    // End-Stake Panalty Reward
    uint16 constant PENALTY_RATE = 1700; // pre-mature end-stake penalty
    uint16 constant RESERVOIR_PENALTY_REWARD = 3427;
    uint16 constant SHORT_STAKER_PENALTY_REWARD = 1311;
    uint16 constant MED_LONG_STAKER_PENALTY_REWARD = 2562;
    uint16 constant TEAM_PENALTY_REWARD = 1500;
    uint16 constant BURN_PENALTY_REWARD = 1200;


    // address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant DAI = 0xaD6D458402F60fD3Bd25163575031ACDce07538D; // ropsten

    // address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // mainnet
    // address constant WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab; // ropsten
    address constant WETH = 0xEb59fE75AC86dF3997A990EDe100b90DDCf9a826; // local

    IUniswapRouterV2 public constant UNISWAP_ROUTER = IUniswapRouterV2(
        // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D // mainnet
        // 0xf164fC0Ec4E93095b804a4795bBe1e041497b92a // ropsten
        0x57079e0d0657890218C630DA5248A1103a1b4ad0 // local
    );

    IGriseToken public GRISE_CONTRACT;
    address public griseGateKeeper;

    uint256 public latestDaiEquivalent;
    address[] internal _path = [address(GRISE_CONTRACT), WETH, DAI];

    constructor() {
        griseGateKeeper = msg.sender;
    }

    struct Stake {
        uint256 stakesShares;
        uint256 stakedAmount;
        uint256 rewardAmount;
        StakeType stakeType;
        uint64 totalOccupiedSlot;
        uint64 startDay;
        uint64 lockDays;
        uint64 finalDay;
        uint64 closeDay;
        uint256 scrapeDay;
        uint256 daiEquivalent;
        bool isActive;
    }

    enum StakeType {
        SHORT_TERM,
        MEDIUM_TERM,
        LARGE_TERM
    }

    struct StakeCapping {
        uint256 minStakingAmount;
        uint256 stakingSlotCount;
        uint256 maxStakingSlot;
    }

    struct StakeMinMaxDay{
        uint256 minStakeDay;
        uint256 maxStakeDay;
    }

    mapping(address => uint256) public stakeCount;
    mapping(address => mapping(bytes16 => uint256)) public scrapes;
    mapping(address => mapping(bytes16 => Stake)) public stakes;

    mapping(uint256 => uint256) public scheduledToEnd;
    mapping(uint256 => uint256) public totalPenalties;
    mapping(uint256 => uint256) public totalPenaltiesPerShares;

    mapping(StakeType => StakeMinMaxDay) public stakeDayLimit;
    mapping(StakeType => mapping(uint8 => StakeCapping)) public stakeCaps;

    // Stake brake Penality Reward
    mapping(uint256 => uint256) internal reservoirReward;
    mapping(uint256 => uint256) internal stakerReward;
}
