// SPDX-License-Identifier: --🦉--

pragma solidity =0.7.6;

/*
 __      __.___  ____________________
/  \    /  \   |/   _____/\_   _____/
\   \/\/   /   |\_____  \  |    __)_
 \        /|   |/        \ |        \
  \__/\  / |___/_______  //_______  /
       \/              \/         \/

The Wise Foundation is an unincorporated nonprofit association formed in February 2020.
The WISE contract and various related software and websites are being wholly funded and
developed by The Wise Foundation. Visit https://wisetoken.net/ for more information.

*/

import './Interfaces.sol';

contract LiquidityTransformer is usingProvable {

    using SafeMathLT for uint256;
    using SafeMathLT for uint128;

    IWiseToken public WISE_CONTRACT;
    UniswapV2Pair public UNISWAP_PAIR;

    UniswapRouterV2 public constant UNISWAP_ROUTER = UniswapRouterV2(
        // 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D // mainnet
        // 0xf164fC0Ec4E93095b804a4795bBe1e041497b92a // ropsten
        0x57079e0d0657890218C630DA5248A1103a1b4ad0 // local
    );

    RefundSponsorI public constant REFUND_SPONSOR = RefundSponsorI(
        // 0xc3FC68dDdB1bf4Cb61307eEf89729DC317f2325a // mainnet
        // 0x025cA911ad05425EfA6D145944af85aB4E12778f // ropsten
        0x7EDBCfFa2bBEdf72c34073C6786dE47299cD7368 // local
    );

    address payable constant TEAM_ADDRESS = 0xa803c226c8281550454523191375695928DcFE92;
    address public TOKEN_DEFINER = 0xa803c226c8281550454523191375695928DcFE92;

    // address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // mainnet
    // address constant WETH = 0xc778417E063141139Fce010982780140Aa0cD5Ab; // ropsten
    address constant WETH = 0xEb59fE75AC86dF3997A990EDe100b90DDCf9a826; // local

    uint8 constant INVESTMENT_DAYS = 50;

    uint128 constant THRESHOLD_LIMIT_MIN = 1 ether;
    uint128 constant THRESHOLD_LIMIT_MAX = 50 ether;
    uint128 constant TEAM_ETHER_MAX = 2000 ether;
    uint128 constant MIN_INVEST = 50000000 gwei;
    uint128 constant DAILY_MAX_SUPPLY = 10000000;

    uint256 constant YODAS_PER_WISE = 10 ** uint256(18);
    uint256 constant NUM_RANDOM_BYTES_REQUESTED = 7;

    struct Globals {
        uint64 generatedDays;
        uint64 generationDayBuffer;
        uint64 generationTimeout;
        uint64 preparedReferrals;
        uint256 totalTransferTokens;
        uint256 totalWeiContributed;
        uint256 totalReferralTokens;
    }

    Globals public g;

    mapping(uint256 => uint256) dailyMinSupply;
    mapping(uint256 => uint256) public dailyTotalSupply;
    mapping(uint256 => uint256) public dailyTotalInvestment;

    mapping(uint256 => uint256) public investorAccountCount;
    mapping(uint256 => mapping(uint256 => address)) public investorAccounts;
    mapping(address => mapping(uint256 => uint256)) public investorBalances;

    mapping(address => uint256) public referralAmount;
    mapping(address => uint256) public referralTokens;
    mapping(address => uint256) public investorTotalBalance;
    mapping(address => uint256) originalInvestment;

    uint256 public referralAccountCount;
    uint256 public uniqueInvestorCount;

    mapping (uint256 => address) public uniqueInvestors;
    mapping (uint256 => address) public referralAccounts;

    event GeneratingRandomSupply(
        uint256 indexed investmentDay
    );

    event GeneratedRandomSupply(
        uint256 indexed investmentDay,
        uint256 randomSupply
    );

    event GeneratedStaticSupply(
        uint256 indexed investmentDay,
        uint256 staticSupply
    );

    event GenerationStatus(
        uint64 indexed investmentDay,
        bool result
    );

    event LogNewProvableQuery(
        string description
    );

    event ReferralAdded(
        address indexed referral,
        address indexed referee,
        uint256 amount
    );

    event UniSwapResult(
        uint256 amountToken,
        uint256 amountETH,
        uint256 liquidity
    );

    event WiseReservation(
        address indexed sender,
        uint256 indexed investmentDay,
        uint256 amount
    );

    modifier afterInvestmentPhase() {
        require(
            _currentWiseDay() > INVESTMENT_DAYS,
            'WISE: ongoing investment phase'
        );
        _;
    }

    modifier afterUniswapTransfer() {
        require (
            g.generatedDays > 0 &&
            g.totalWeiContributed == 0,
            'WISE: forward liquidity first'
        );
        _;
    }

    modifier investmentDaysRange(uint256 _investmentDay) {
        require(
            _investmentDay > 0 &&
            _investmentDay <= INVESTMENT_DAYS,
            'WISE: not in initial investment days range'
        );
        _;
    }

    modifier investmentEntryAmount(uint256 _days) {
        require(
            msg.value >= MIN_INVEST * _days,
            'WISE: investment below minimum'
        );
        _;
    }

    modifier onlyFundedDays(uint256 _investmentDay) {
        require(
            dailyTotalInvestment[_investmentDay] > 0,
            'WISE: no investments on that day'
        );
        _;
    }

    modifier refundSponsorDynamic() {
        uint256 gasStart = gasleft();
        _;
        uint256 gasSpent = (21000 + gasStart - gasleft()).mul(tx.gasprice);
        gasSpent = msg.value.div(10) > gasSpent ? gasSpent : msg.value.div(10);
        REFUND_SPONSOR.addGasRefund(msg.sender, gasSpent);
    }

    modifier refundSponsorFixed() {
        uint256 gasStart = gasleft();
        _;
        uint256 gasSpent = (21000 + gasStart - gasleft()).mul(tx.gasprice);
        gasSpent = gasSpent > 5000000000000000 ? 5000000000000000 : gasSpent;
        REFUND_SPONSOR.addGasRefund(msg.sender, gasSpent);
    }

    modifier onlyTokenDefiner() {
        require(
            msg.sender == TOKEN_DEFINER,
            'WISE: wrong sender'
        );
        _;
    }

    receive() external payable {
        require (
            msg.sender == address(UNISWAP_ROUTER) ||
            msg.sender == TEAM_ADDRESS ||
            msg.sender == TOKEN_DEFINER,
            'WISE: direct deposits disabled'
        );
    }

    function defineToken(
        address _wiseToken,
        address _uniswapPair
    )
        external
        onlyTokenDefiner
    {
        WISE_CONTRACT = IWiseToken(_wiseToken);
        UNISWAP_PAIR = UniswapV2Pair(_uniswapPair);
    }

    function revokeAccess()
        external
        onlyTokenDefiner
    {
        TOKEN_DEFINER = address(0x0);
    }

    constructor(address _wiseToken, address _uniswapPair) {

        WISE_CONTRACT = IWiseToken(_wiseToken);
        UNISWAP_PAIR = UniswapV2Pair(_uniswapPair);

        OAR = OracleAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);

        provable_setProof(proofType_Ledger);
        provable_setCustomGasPrice(10000000000);

        dailyMinSupply[1] = 5000000;
        dailyMinSupply[2] = 5000000;
        dailyMinSupply[3] = 5000000;
        dailyMinSupply[4] = 5000000;
        dailyMinSupply[5] = 5000000;
        dailyMinSupply[6] = 5000000;
        dailyMinSupply[7] = 5000000;

        dailyMinSupply[8] = 4500000;
        dailyMinSupply[9] = 5000000;

        dailyMinSupply[10] = 4500000;
        dailyMinSupply[11] = 5000000;
        dailyMinSupply[12] = 1;
        dailyMinSupply[13] = 5000000;
        dailyMinSupply[14] = 4000000;
        dailyMinSupply[15] = 5000000;
        dailyMinSupply[16] = 4000000;
        dailyMinSupply[17] = 4000000;
        dailyMinSupply[18] = 5000000;
        dailyMinSupply[19] = 1;

        dailyMinSupply[20] = 5000000;
        dailyMinSupply[21] = 3500000;
        dailyMinSupply[22] = 5000000;
        dailyMinSupply[23] = 3500000;
        dailyMinSupply[24] = 5000000;
        dailyMinSupply[25] = 3500000;
        dailyMinSupply[26] = 1;
        dailyMinSupply[27] = 5000000;
        dailyMinSupply[28] = 5000000;
        dailyMinSupply[29] = 3000000;

        dailyMinSupply[30] = 5000000;
        dailyMinSupply[31] = 3000000;
        dailyMinSupply[32] = 5000000;
        dailyMinSupply[33] = 1;
        dailyMinSupply[34] = 5000000;
        dailyMinSupply[35] = 2500000;
        dailyMinSupply[36] = 2500000;
        dailyMinSupply[37] = 5000000;
        dailyMinSupply[38] = 2500000;
        dailyMinSupply[39] = 5000000;

        dailyMinSupply[40] = 1;
        dailyMinSupply[41] = 5000000;
        dailyMinSupply[42] = 1;
        dailyMinSupply[43] = 5000000;
        dailyMinSupply[44] = 1;
        dailyMinSupply[45] = 5000000;
        dailyMinSupply[46] = 1;
        dailyMinSupply[47] = 1;
        dailyMinSupply[48] = 1;
        dailyMinSupply[49] = 5000000;
        dailyMinSupply[50] = 5000000;
    }


    //  WISE RESERVATION (EXTERNAL FUNCTIONS)  //
    //  -------------------------------------  //

    /** @dev Performs reservation of WISE tokens with ETH
      * @param _investmentDays array of reservation days.
      * @param _referralAddress referral address for bonus.
      */
    function reserveWise(
        uint8[] calldata _investmentDays,
        address _referralAddress
    )
        external
        payable
        refundSponsorDynamic
        investmentEntryAmount(_investmentDays.length)
    {
        checkInvestmentDays(
            _investmentDays,
            _currentWiseDay()
        );

        _reserveWise(
            _investmentDays,
            _referralAddress,
            msg.sender,
            msg.value
        );
    }

    /** @notice Allows reservation of WISE tokens with other ERC20 tokens
      * @dev this will require LT contract to be approved as spender
      * @param _tokenAddress address of an ERC20 token to use
      * @param _tokenAmount amount of tokens to use for reservation
      * @param _investmentDays array of reservation days
      * @param _referralAddress referral address for bonus
      */
    function reserveWiseWithToken(
        address _tokenAddress,
        uint256 _tokenAmount,
        uint8[] calldata _investmentDays,
        address _referralAddress
    )
        external
        refundSponsorFixed
    {
        IERC20Token _token = IERC20Token(
            _tokenAddress
        );

        _token.transferFrom(
            msg.sender,
            address(this),
            _tokenAmount
        );

        _token.approve(
            address(UNISWAP_ROUTER),
            _tokenAmount
        );

        address[] memory _path = preparePath(
            _tokenAddress
        );

        uint256[] memory amounts =
        UNISWAP_ROUTER.swapExactTokensForETH(
            _tokenAmount,
            0,
            _path,
            address(this),
            block.timestamp.add(2 hours)
        );

        require(
            amounts[1] >= MIN_INVEST * _investmentDays.length,
            'WISE: investment below minimum'
        );

        checkInvestmentDays(
            _investmentDays,
            _currentWiseDay()
        );

        _reserveWise(
            _investmentDays,
            _referralAddress,
            msg.sender,
            amounts[1]
        );
    }

    //  WISE RESERVATION (INTERNAL FUNCTIONS)  //
    //  -------------------------------------  //

    /** @notice Distributes ETH equaly between selected reservation days
      * @dev this will require LT contract to be approved as a spender
      * @param _investmentDays array of selected reservation days
      * @param _referralAddress referral address for bonus
      * @param _senderAddress address of the investor
      * @param _senderValue amount of ETH contributed
      */
    function _reserveWise(
        uint8[] memory _investmentDays,
        address _referralAddress,
        address _senderAddress,
        uint256 _senderValue
    )
        internal
    {
        require(
            _senderAddress != _referralAddress,
            'WISE: must be a different address'
        );

        require(
            notContract(_referralAddress),
            'WISE: invalid referral address'
        );

        uint256 _investmentBalance = _referralAddress == address(0x0)
            ? _senderValue // no referral bonus
            : _senderValue.mul(1100).div(1000);

        uint256 _totalDays = _investmentDays.length;
        uint256 _dailyAmount = _investmentBalance.div(_totalDays);
        uint256 _leftOver = _investmentBalance.mod(_totalDays);

        _addBalance(
            _senderAddress,
            _investmentDays[0],
            _dailyAmount.add(_leftOver)
        );

        for (uint8 _i = 1; _i < _totalDays; _i++) {
            _addBalance(
                _senderAddress,
                _investmentDays[_i],
                _dailyAmount
            );
        }

        _trackInvestors(
            _senderAddress,
            _investmentBalance
        );

        if (_referralAddress != address(0x0)) {

            _trackReferrals(_referralAddress, _senderValue);

            emit ReferralAdded(
                _referralAddress,
                _senderAddress,
                _senderValue
            );
        }

        originalInvestment[_senderAddress] += _senderValue;
        g.totalWeiContributed += _senderValue;
    }

    /** @notice Allocates investors balance to specific day
      * @param _senderAddress investors wallet address
      * @param _investmentDay selected investment day
      * @param _investmentBalance amount invested (with bonus)
      */
    function _addBalance(
        address _senderAddress,
        uint256 _investmentDay,
        uint256 _investmentBalance
    )
        internal
    {
        if (investorBalances[_senderAddress][_investmentDay] == 0) {
            investorAccounts[_investmentDay][investorAccountCount[_investmentDay]] = _senderAddress;
            investorAccountCount[_investmentDay]++;
        }

        investorBalances[_senderAddress][_investmentDay] += _investmentBalance;
        dailyTotalInvestment[_investmentDay] += _investmentBalance;

        emit WiseReservation(
            _senderAddress,
            _investmentDay,
            _investmentBalance
        );
    }

    //  WISE RESERVATION (PRIVATE FUNCTIONS)  //
    //  ------------------------------------  //

    /** @notice Tracks investorTotalBalance and uniqueInvestors
      * @dev used in _reserveWise() internal function
      * @param _investorAddress address of the investor
      * @param _value ETH amount invested (with bonus)
      */
    function _trackInvestors(address _investorAddress, uint256 _value) private {
        // if (investorTotalBalance[_investorAddress] == 0) uniqueInvestors.push(_investorAddress);
        if (investorTotalBalance[_investorAddress] == 0) {
            uniqueInvestors[
            uniqueInvestorCount] = _investorAddress;
            uniqueInvestorCount++;
        }
        investorTotalBalance[_investorAddress] += _value;
    }

    /** @notice Tracks referralAmount and referralAccounts
      * @dev used in _reserveWise() internal function
      * @param _referralAddress address of the referrer
      * @param _value ETH amount referred during reservation
      */
    function _trackReferrals(address _referralAddress, uint256 _value) private {
        if (referralAmount[_referralAddress] == 0) {
            referralAccounts[
            referralAccountCount] = _referralAddress;
            referralAccountCount++;
        }
        referralAmount[_referralAddress] += _value;
    }


    //  SUPPLY GENERATION (EXTERNAL FUNCTION)  //
    //  -------------------------------------  //

    /** @notice Allows to generate supply for past funded days
      * @param _investmentDay investemnt day index (1-50)
      */
    function generateSupply(
        uint64 _investmentDay
    )
        external
        investmentDaysRange(_investmentDay)
        onlyFundedDays(_investmentDay)
    {
        require(
            _investmentDay < _currentWiseDay(),
            'WISE: investment day must be in past'
        );

        require(
            g.generationDayBuffer == 0,
            'WISE: supply generation in progress'
        );

        require(
            dailyTotalSupply[_investmentDay] == 0,
            'WISE: supply already generated'
        );

        g.generationDayBuffer = _investmentDay;
        g.generationTimeout = uint64(block.timestamp.add(2 hours));

        DAILY_MAX_SUPPLY - dailyMinSupply[_investmentDay] == dailyMinSupply[_investmentDay]
            ? _generateStaticSupply(_investmentDay)
            : _generateRandomSupply(_investmentDay);
    }


    //  SUPPLY GENERATION (INTERNAL FUNCTIONS)  //
    //  --------------------------------------  //

    /** @notice Generates supply for days with static supply
      * @param _investmentDay investemnt day index (1-50)
      */
    function _generateStaticSupply(
        uint256 _investmentDay
    )
        internal
    {
        dailyTotalSupply[_investmentDay] = dailyMinSupply[_investmentDay] * YODAS_PER_WISE;
        g.totalTransferTokens += dailyTotalSupply[_investmentDay];

        g.generatedDays++;
        g.generationDayBuffer = 0;
        g.generationTimeout = 0;

        emit GeneratedStaticSupply(
            _investmentDay,
            dailyTotalSupply[_investmentDay]
        );
    }

    /** @notice Generates supply for days with random supply
      * @dev uses provable api to request provable_newRandomDSQuery
      * @param _investmentDay investemnt day index (1-50)
      */
    function _generateRandomSupply(
        uint256 _investmentDay
    )
        internal
    {
        uint256 QUERY_EXECUTION_DELAY = 0;
        uint256 GAS_FOR_CALLBACK = 200000;
        provable_newRandomDSQuery(
            QUERY_EXECUTION_DELAY,
            NUM_RANDOM_BYTES_REQUESTED,
            GAS_FOR_CALLBACK
        );

        emit GeneratingRandomSupply(_investmentDay);
        emit LogNewProvableQuery("Provable query was sent, standing by for the answer...");
    }

    //  SUPPLY GENERATION (ORACLE FUNCTIONS)  //
    //  ------------------------------------  //

    /** @notice Function that generates random supply
      * @dev expected to be called by oracle within 2 hours
      * time-frame, otherwise __timeout() can be performed
      */
    function __callback(
        bytes32 _queryId,
        string memory _result,
        bytes memory _proof
    )
        public
        override
    {
        require(
            msg.sender == provable_cbAddress(),
            'WISE: can only be called by Oracle'
        );

        require(
            g.generationDayBuffer > 0 &&
            g.generationDayBuffer <= INVESTMENT_DAYS,
            'WISE: incorrect generation day'
        );

        if (
            provable_randomDS_proofVerify__returnCode(
                _queryId,
                _result,
                _proof
            ) != 0
        ) {

            g.generationDayBuffer = 0;
            g.generationTimeout = 0;

            emit GenerationStatus(
                g.generationDayBuffer, false
            );

        } else {

            g.generatedDays = g.generatedDays + 1;
            uint256 _investmentDay = g.generationDayBuffer;

            uint256 currentDayMaxSupply = DAILY_MAX_SUPPLY.sub(dailyMinSupply[_investmentDay]);
            uint256 ceilingDayMaxSupply = currentDayMaxSupply.sub(dailyMinSupply[_investmentDay]);

            uint256 randomSupply = uint256(
                keccak256(
                    abi.encodePacked(_result)
                )
            ) % ceilingDayMaxSupply;

            require(
                dailyTotalSupply[_investmentDay] == 0,
                'WISE: supply already generated!'
            );

            dailyTotalSupply[_investmentDay] = dailyMinSupply[_investmentDay]
                .add(randomSupply)
                .mul(YODAS_PER_WISE);

            g.totalTransferTokens = g.totalTransferTokens
                .add(dailyTotalSupply[_investmentDay]);

            emit GeneratedRandomSupply(
                _investmentDay,
                dailyTotalSupply[_investmentDay]
            );

            emit GenerationStatus(
                g.generationDayBuffer, true
            );

            g.generationDayBuffer = 0;
            g.generationTimeout = 0;

        }
    }

    /** @notice Allows to reset expected oracle callback
      * @dev resets generationDayBuffer to retry callback
      * assigns static supply if no callback within a day
      */
    function __timeout()
        external
    {
        require(
            g.generationTimeout > 0 &&
            g.generationTimeout < block.timestamp,
            'WISE: still awaiting!'
        );

        uint64 _investmentDay = g.generationDayBuffer;

        require(
            _investmentDay > 0 &&
            _investmentDay <= INVESTMENT_DAYS,
            'WISE: incorrect generation day'
        );

        require(
            dailyTotalSupply[_investmentDay] == 0,
            'WISE: supply already generated!'
        );

        if (_currentWiseDay() - _investmentDay > 1) {

            dailyTotalSupply[_investmentDay] = dailyMinSupply[1]
                .mul(YODAS_PER_WISE);

            g.totalTransferTokens = g.totalTransferTokens
                .add(dailyTotalSupply[_investmentDay]);

            g.generatedDays = g.generatedDays + 1;

            emit GeneratedStaticSupply(
                _investmentDay,
                dailyTotalSupply[_investmentDay]
            );

            emit GenerationStatus(
                _investmentDay, true
            );

        } else {
            emit GenerationStatus(
                _investmentDay, false
            );
        }
        g.generationDayBuffer = 0;
        g.generationTimeout = 0;
    }


    //  PRE-LIQUIDITY GENERATION FUNCTION  //
    //  ---------------------------------  //

    /** @notice Pre-calculates amount of tokens each referrer will get
      * @dev must run this for all referrer addresses in batches
      * converts _referralAmount to _referralTokens based on dailyRatio
      */
    function prepareReferralBonuses(
        uint256 _referralBatchFrom,
        uint256 _referralBatchTo
    )
        external
        afterInvestmentPhase
    {
        require(
            _referralBatchFrom < _referralBatchTo,
            'WISE: incorrect referral batch'
        );

        require (
            g.preparedReferrals < referralAccountCount,
            'WISE: all referrals already prepared'
        );

        uint256 _totalRatio = g.totalTransferTokens.div(g.totalWeiContributed);

        for (uint256 i = _referralBatchFrom; i < _referralBatchTo; i++) {
            address _referralAddress = referralAccounts[i];
            uint256 _referralAmount = referralAmount[_referralAddress];
            if (referralAmount[_referralAddress] > 0) {
                referralAmount[_referralAddress] = 0;
                if (_referralAmount >= THRESHOLD_LIMIT_MIN) {
                    _referralAmount >= THRESHOLD_LIMIT_MAX
                        ? _fullReferralBonus(_referralAddress, _referralAmount, _totalRatio)
                        : _familyReferralBonus(_referralAddress, _totalRatio);

                    g.totalReferralTokens = g.totalReferralTokens.add(
                        referralTokens[_referralAddress]
                    );
                }
                g.preparedReferrals++;
            }
        }
    }

    /** @notice performs token allocation for 10% of referral amount
      * @dev after liquidity is formed referrer can withdraw this amount
      * additionally this will give CM status to the referrer address
      */
    function _fullReferralBonus(address _referralAddress, uint256 _referralAmount, uint256 _ratio) internal {
        referralTokens[_referralAddress] = _referralAmount.div(10).mul(_ratio);
        WISE_CONTRACT.giveStatus(_referralAddress);
    }

    /** @notice performs token allocation for family bonus referrals
      * @dev after liquidity is formed referrer can withdraw this amount
      */
    function _familyReferralBonus(address _referralAddress, uint256 _ratio) internal {
        referralTokens[_referralAddress] = MIN_INVEST.mul(_ratio);
    }


    //  LIQUIDITY GENERATION FUNCTION  //
    //  -----------------------------  //

    /** @notice Creates initial liquidity on Uniswap by forwarding
      * reserved tokens equivalent to ETH contributed to the contract
      * @dev check addLiquidityETH documentation
      */
    function forwardLiquidity(/*🦄*/)
        external
        afterInvestmentPhase
    {
        require(
            g.generatedDays == fundedDays(),
            'WISE: must generate supply for all days'
        );

        require (
            g.preparedReferrals == referralAccountCount,
            'WISE: must prepare all referrals'
        );

        require (
            g.totalTransferTokens > 0,
            'WISE: must have tokens to transfer'
        );

        uint256 _balance = g.totalWeiContributed;
        uint256 _buffer = g.totalTransferTokens + g.totalReferralTokens;

        _balance = _balance.sub(
            _teamContribution(
                _balance.div(10)
            )
        );

        _buffer = _buffer.mul(_balance).div(
            g.totalWeiContributed
        );

        WISE_CONTRACT.mintSupply(
            address(this), _buffer
        );

        WISE_CONTRACT.approve(
            address(UNISWAP_ROUTER), _buffer
        );

        (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        ) =

        UNISWAP_ROUTER.addLiquidityETH{value: _balance}(
            address(WISE_CONTRACT),
            _buffer,
            0,
            0,
            address(0x0),
            block.timestamp.add(2 hours)
        );

        g.totalTransferTokens = 0;
        g.totalReferralTokens = 0;
        g.totalWeiContributed = 0;

        emit UniSwapResult(
            amountToken, amountETH, liquidity
        );
    }


    //  WISE TOKEN PAYOUT FUNCTIONS (INDIVIDUAL)  //
    //  ----------------------------------------  //

    /** @notice Allows to mint all the tokens
      * from investor and referrer perspectives
      * @dev can be called after forwardLiquidity()
      */
    function $getMyTokens(/*💰*/)
        external
        afterUniswapTransfer
    {
        payoutInvestorAddress(msg.sender);
        payoutReferralAddress(msg.sender);
    }

    /** @notice Allows to mint tokens for specific investor address
      * @dev aggregades investors tokens across all investment days
      * and uses WISE_CONTRACT instance to mint all the WISE tokens
      * @param _investorAddress requested investor calculation address
      * @return _payout amount minted to the investors address
      */
    function payoutInvestorAddress(
        address _investorAddress
    )
        public
        afterUniswapTransfer
        returns (uint256 _payout)
    {
        for (uint8 i = 1; i <= INVESTMENT_DAYS; i++) {
            if (investorBalances[_investorAddress][i] > 0) {
                _payout += investorBalances[_investorAddress][i].mul(
                    _calculateDailyRatio(i)
                ).div(100E18);
                investorBalances[_investorAddress][i] = 0;
            }
        }
        if (_payout > 0) {
            WISE_CONTRACT.mintSupply(
                _investorAddress,
                _payout
            );
        }
    }

    /** @notice Allows to mint tokens for specific referrer address
      * @dev must be pre-calculated in prepareReferralBonuses()
      * @param _referralAddress referrer payout address
      * @return _referralTokens amount minted to the referrer address
      */
    function payoutReferralAddress(
        address _referralAddress
    ) public
        afterUniswapTransfer
        returns (uint256 _referralTokens)
    {
        _referralTokens = referralTokens[_referralAddress];
        if (referralTokens[_referralAddress] > 0) {
            referralTokens[_referralAddress] = 0;
            WISE_CONTRACT.mintSupply(
                _referralAddress,
                _referralTokens
            );
        }
    }

    //  WISE TOKEN PAYOUT FUNCTIONS (BATCHES)  //
    //  -------------------------------------  //

    /** @notice Allows to mint tokens for specific investment day
      * recommended batch size is up to 50 addresses per call
      * @param _investmentDay processing investment day
      * @param _investorBatchFrom batch starting index
      * @param _investorBatchTo bach finishing index
      */
    function payoutInvestmentDayBatch(
        uint256 _investmentDay,
        uint256 _investorBatchFrom,
        uint256 _investorBatchTo
    )
        external
        afterUniswapTransfer
        onlyFundedDays(_investmentDay)
    {
        require(
            _investorBatchFrom < _investorBatchTo,
            'WISE: incorrect investment batch'
        );

        uint256 _dailyRatio = _calculateDailyRatio(_investmentDay);

        for (uint256 i = _investorBatchFrom; i < _investorBatchTo; i++) {
            address _investor = investorAccounts[_investmentDay][i];
            uint256 _balance = investorBalances[_investor][_investmentDay];
            uint256 _payout = _balance.mul(_dailyRatio).div(100E18);

            if (investorBalances[_investor][_investmentDay] > 0) {
                investorBalances[_investor][_investmentDay] = 0;
                WISE_CONTRACT.mintSupply(
                    _investor,
                    _payout
                );
            }
        }
    }

    /** @notice Allows to mint tokens for referrers in batches
      * @dev can be called right after forwardLiquidity()
      * recommended batch size is up to 50 addresses per call
      * @param _referralBatchFrom batch starting index
      * @param _referralBatchTo bach finishing index
      */
    function payoutReferralBatch(
        uint256 _referralBatchFrom,
        uint256 _referralBatchTo
    )
        external
        afterUniswapTransfer
    {
        require(
            _referralBatchFrom < _referralBatchTo,
            'WISE: incorrect referral batch'
        );

        for (uint256 i = _referralBatchFrom; i < _referralBatchTo; i++) {
            address _referralAddress = referralAccounts[i];
            uint256 _referralTokens = referralTokens[_referralAddress];
            if (referralTokens[_referralAddress] > 0) {
                referralTokens[_referralAddress] = 0;
                WISE_CONTRACT.mintSupply(
                    _referralAddress,
                    _referralTokens
                );
            }
        }
    }

    //  INFO VIEW FUNCTIONS (PERSONAL)  //
    //  ------------------------------  //

    /** @notice checks for callers investment amount on specific day (with bonus)
      * @return total amount invested across all investment days (with bonus)
      */
    function myInvestmentAmount(uint256 _investmentDay) external view returns (uint256) {
        return investorBalances[msg.sender][_investmentDay];
    }

    /** @notice checks for callers investment amount on each day (with bonus)
      * @return _myAllDays total amount invested across all days (with bonus)
      */
    function myInvestmentAmountAllDays() external view returns (uint256[51] memory _myAllDays) {
        for (uint256 i = 1; i <= INVESTMENT_DAYS; i++) {
            _myAllDays[i] = investorBalances[msg.sender][i];
        }
    }

    /** @notice checks for callers total investment amount (with bonus)
      * @return total amount invested across all investment days (with bonus)
      */
    function myTotalInvestmentAmount() external view returns (uint256) {
        return investorTotalBalance[msg.sender];
    }


    //  INFO VIEW FUNCTIONS (GLOBAL)  //
    //  ----------------------------  //

    /** @notice checks for investors count on specific day
      * @return investors count for specific day
      */
    function investorsOnDay(uint256 _investmentDay) public view returns (uint256) {
        return dailyTotalInvestment[_investmentDay] > 0 ? investorAccountCount[_investmentDay] : 0;
    }

    /** @notice checks for investors count on each day
      * @return _allInvestors array with investors count for each day
      */
    function investorsOnAllDays() external view returns (uint256[51] memory _allInvestors) {
        for (uint256 i = 1; i <= INVESTMENT_DAYS; i++) {
            _allInvestors[i] = investorsOnDay(i);
        }
    }

    /** @notice checks for investment amount on each day
      * @return _allInvestments array with investment amount for each day
      */
    function investmentsOnAllDays() external view returns (uint256[51] memory _allInvestments) {
        for (uint256 i = 1; i <= INVESTMENT_DAYS; i++) {
            _allInvestments[i] = dailyTotalInvestment[i];
        }
    }

    /** @notice checks for supply amount on each day
      * @return _allSupply array with supply amount for each day
      */
    function supplyOnAllDays() external view returns (uint256[51] memory _allSupply) {
        for (uint256 i = 1; i <= INVESTMENT_DAYS; i++) {
            _allSupply[i] = dailyTotalSupply[i];
        }
    }


    //  HELPER FUNCTIONS (PURE)  //
    //  -----------------------  //

    /** @notice checks that provided days are valid for investemnt
      * @dev used in reserveWise() and reserveWiseWithToken()
      */
    function checkInvestmentDays(
        uint8[] memory _investmentDays,
        uint64 _wiseDay
    )
        internal
        pure
    {
        for (uint8 _i = 0; _i < _investmentDays.length; _i++) {
            require(
                _investmentDays[_i] >= _wiseDay,
                'WISE: investment day already passed'
            );
            require(
                _investmentDays[_i] > 0 &&
                _investmentDays[_i] <= INVESTMENT_DAYS,
                'WISE: incorrect investment day'
            );
        }
    }

    /** @notice prepares path variable for uniswap to exchange tokens
      * @dev used in reserveWiseWithToken() swapExactTokensForETH call
      * @param _tokenAddress ERC20 token address to be swapped for ETH
      * @return _path that is used to swap tokens for ETH on uniswap
      */
    function preparePath(
        address _tokenAddress
    ) internal pure returns (
        address[] memory _path
    ) {
        _path = new address[](2);
        _path[0] = _tokenAddress;
        _path[1] = WETH;
    }

    /** @notice keeps team contribution at caped level
      * @dev subtracts amount during forwardLiquidity()
      * @return ETH amount the team is allowed to withdraw
      */
    function _teamContribution(
        uint256 _teamAmount
    ) internal pure returns (uint256) {
        return _teamAmount > TEAM_ETHER_MAX ? TEAM_ETHER_MAX : _teamAmount;
    }

    /** @notice checks for invesments on all days
      * @dev used in forwardLiquidity() requirements
      * @return $fundedDays - amount of funded days 0-50
      */
    function fundedDays() public view returns (
        uint8 $fundedDays
    ) {
        for (uint8 i = 1; i <= INVESTMENT_DAYS; i++) {
            if (dailyTotalInvestment[i] > 0) $fundedDays++;
        }
    }

    /** @notice WISE equivalent in ETH price calculation
      * @dev returned value has 100E18 precision - divided later on
      * @return token price for specific day based on total investement
      */
    function _calculateDailyRatio(
        uint256 _investmentDay
    ) internal view returns (uint256) {

        uint256 dailyRatio = dailyTotalSupply[_investmentDay].mul(100E18)
            .div(dailyTotalInvestment[_investmentDay]);

        uint256 remainderCheck = dailyTotalSupply[_investmentDay].mul(100E18)
            .mod(dailyTotalInvestment[_investmentDay]);

        return remainderCheck == 0 ? dailyRatio : dailyRatio.add(1);
    }

    //  TIMING FUNCTIONS  //
    //  ----------------  //

    /** @notice shows current day of WiseToken
      * @dev value is fetched from WISE_CONTRACT
      * @return iteration day since WISE inception
      */
    function _currentWiseDay() public view returns (uint64) {
        return WISE_CONTRACT.currentWiseDay();
    }

    //  EMERGENCY REFUND FUNCTIONS  //
    //  --------------------------  //

    /** @notice allows refunds if funds are stuck
      * @param _investor address to be refunded
      * @return _amount refunded to the investor
      */
    function requestRefund(
        address payable _investor,
        address payable _succesor
    ) external returns (
        uint256 _amount
    ) {
        require(
            g.totalWeiContributed > 0  &&
            originalInvestment[_investor] > 0 &&
            _currentWiseDay() > INVESTMENT_DAYS + 10,
           'WISE: liquidity successfully forwarded to uniswap 🦄'
        );

        // refunds the investor
        _amount = originalInvestment[_investor];
        originalInvestment[_investor] = 0;
        _succesor.transfer(_amount);

        // deny possible comeback
        g.totalTransferTokens = 0;
    }

    /** @notice allows to withdraw team funds for the work
      * strictly only after the uniswap liquidity is formed
      * @param _amount value to withdraw from the contract
      */
    function requestTeamFunds(
        uint256 _amount
    )
        external
        afterUniswapTransfer
    {
        TEAM_ADDRESS.transfer(_amount);
    }

    function notContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size == 0);
    }

}

library SafeMathLT {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, 'WISE: addition overflow');
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, 'WISE: subtraction overflow');
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {

        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, 'WISE: multiplication overflow');

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, 'WISE: division by zero');
        uint256 c = a / b;
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, 'WISE: modulo by zero');
        return a % b;
    }
}

import './provableAPI_0.6.sol';
