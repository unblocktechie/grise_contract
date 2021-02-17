// SPDX-License-Identifier: --🦉--

pragma solidity =0.7.6;

import "./Utils.sol";

contract GriseToken is Utils {

    using SafeMath for uint256;

    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    address public LIQUIDITY_TRANSFORMER;
    address public transformerGateKeeper;
    address public STAKE_TRANSFORMER;
    address public stakeGateKeeper;

    /**
     * @dev initial private
     */
    string private _name;
    string private _symbol;
    uint8 private _decimal = 18;

    /**
     * @dev 👻 Initial supply 
     */
    uint256 private _totalSupply = 0;

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor (string memory tokenName, string memory tokenSymbol) {
        _name = tokenName;
        _symbol = tokenSymbol;
        transformerGateKeeper = msg.sender;
        stakeGateKeeper = msg.sender;
        
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the decimals of the token.
     */
    function decimals() public view returns (uint8) {
        return _decimal;
    }

    /**
     * @dev Returns the total supply of the token.
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev Returns the token balance of specific address.
     */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(
        address recipient,
        uint256 amount
    )
        public
        returns (bool)
    {
        amount = amount.mul(TEMP_PRECISION);
        
        _transfer(
            _msgSender(),
            recipient,
            amount
        );

        return true;
    }

    /**
     * @dev Returns approved balance to be spent by another address
     * by using transferFrom method
     */
    function allowance(
        address owner,
        address spender
    )
        public
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev Sets the token allowance to another spender
     */
    function approve(
        address spender,
        uint256 amount
    )
        public
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            amount
        );

        return true;
    }

    /**
     * @dev Allows to transfer tokens on senders behalf
     * based on allowance approved for the executer
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        returns (bool)
    {
        amount = amount.mul(TEMP_PRECISION);
        
        _approve(sender,
            _msgSender(), _allowances[sender][_msgSender()].sub(
                amount
            )
        );

        _transfer(
            sender,
            recipient,
            amount
        );
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * Emits a {Transfer} event.
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    )
        internal
        virtual
    {
        require(
            sender != address(0x0)
        );

        require(
            recipient != address(0x0)
        );

        uint256 stFee;
        uint256 btFee;
        uint256 teamReward;
        
        if (!isStaker[sender]) {
            uint256 GriseWeek = currentGriseWeek();
            uint256 GriseQuater = (GriseWeek.mod(4) != 0)?
                                    GriseWeek.div(4).add(1) :
                                    GriseWeek.div(4);
            
            stFee = _calculateSellTranscFee(amount);

            sellTranscFee[GriseWeek] = 
            sellTranscFee[GriseWeek].add(stFee);
            
            reservoirReward[GriseQuater] = 
            reservoirReward[GriseQuater].add(stFee.mul(RESERVOIR_REWARD)
                                        .div(REWARD_PRECISION_RATE));
            
            stakerReward[GriseWeek] = 
            stakerReward[GriseWeek].add(stFee.mul(STAKER_REWARD)
                                   .div(REWARD_PRECISION_RATE));
            
            tokenHolderReward[GriseWeek] = 
            tokenHolderReward[GriseWeek].add(stFee.mul(TOKEN_HOLDER_REWARD)
                                        .div(REWARD_PRECISION_RATE));
            
            teamReward = stFee.mul(TEAM_SELL_TRANSC_REWARD)
                              .div(REWARD_PRECISION_RATE);
        }

        btFee = _calculateBuyTranscFee(amount);
        
        _balances[sender] =
        _balances[sender].sub(amount);

        _balances[recipient] =
        _balances[recipient].add(amount.sub(btFee).sub(stFee));

        teamReward += btFee.mul(TEAM_BUY_TRANS_REWARD).div(REWARD_PRECISION_RATE);
        
        _balances[TEAM_ADDRESS] = 
        _balances[TEAM_ADDRESS].add(teamReward);

        // Burn Transction fee
        // We will mint token when user comes
        // to claim transction fee reward.
        _totalSupply =
        _totalSupply.sub(stFee.add(btFee).sub(teamReward));

        totalToken[currentGriseWeek()] = _totalSupply.add(stakedToken);
        
        emit Transfer(
            sender,
            recipient,
            amount
        );
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(
        address account,
        uint256 amount
    )
        internal
        virtual
    {
        require(
            account != address(0x0)
        );

        amount = amount.mul(TEMP_PRECISION);
        
        _totalSupply =
        _totalSupply.add(amount);

        _balances[account] =
        _balances[account].add(amount);

        totalToken[currentGriseWeek()] = _totalSupply.add(stakedToken);
        
        emit Transfer(
            address(0x0),
            account,
            amount
        );
    }

    /**
     * @dev Allows to burn tokens if token sender
     * wants to reduce totalSupply() of the token
      */
    function burn(
        uint256 amount
    )
        external
    {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(
        address account,
        uint256 amount
    )
        internal
        virtual
    {
        require(
            account != address(0x0)
        );

        _balances[account] =
        _balances[account].sub(amount);

        _totalSupply =
        _totalSupply.sub(amount);

        totalToken[currentGriseWeek()] = _totalSupply.add(stakedToken);
        
        emit Transfer(
            account,
            address(0x0),
            amount
        );
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    )
        internal
        virtual
    {
        require(
            owner != address(0x0)
        );

        require(
            spender != address(0x0)
        );

        _allowances[owner][spender] = amount;

        emit Approval(
            owner,
            spender,
            amount
        );
    }

    /**
     * @notice ability to define liquidity transformer contract
     * @dev this method renounce transformerGateKeeper access
     * @param _immutableTransformer contract address
     */
    function setLiquidityTransfomer(
        address _immutableTransformer
    )
        external
    {
        require(
            transformerGateKeeper == msg.sender,
            'GRISE: transformer defined'
        );
        LIQUIDITY_TRANSFORMER = _immutableTransformer;
        transformerGateKeeper = address(0x0);
    }

    /**
     * @notice ability to define Staker contract
     * @dev this method renounce stakeGateKeeper access
     * @param _immutableStaker contract address
     */
    function setStakeTransformer(
        address _immutableStaker
    )
        external
    {
        require(
            stakeGateKeeper == msg.sender,
            'GRISE: transformer defined'
        );
        STAKE_TRANSFORMER = _immutableStaker;
        stakeGateKeeper = address(0x0);
    }
    /**
     * @notice allows liquidityTransformer to mint supply
     * @dev executed from liquidityTransformer upon UNISWAP transfer
     * and during reservation payout to contributors and referrers
     * @param _investorAddress address for minting GRISE tokens
     * @param _amount of tokens to mint for _investorAddress
     */
    function mintSupply(
        address _investorAddress,
        uint256 _amount
    )
        external
    {
        require(
            (msg.sender == LIQUIDITY_TRANSFORMER) ||
            (msg.sender == STAKE_TRANSFORMER) ,
            'GRISE: wrong transformer'
        );

        _mint(
            _investorAddress,
            _amount
        );
    }

    /**
     * @notice allows liquidityTransformer to mint supply
     * @dev executed from liquidityTransformer upon UNISWAP transfer
     * and during reservation payout to contributors and referrers
     * @param _investorAddress address for minting GRISE tokens
     * @param _amount of tokens to mint for _investorAddress
     */
    function burnSupply(
        address _investorAddress,
        uint256 _amount
    )
        external
    {
        require(
            msg.sender == STAKE_TRANSFORMER ,
            'GRISE: wrong transformer'
        );

        _burn(
            _investorAddress,
            _amount
        );
    }

    
    function setStaker(address _staker) external {
        
        require(
            msg.sender == STAKE_TRANSFORMER ,
            'GRISE: wrong transformer'
        );
        
        isStaker[_staker] = true;
    }
    
    function resetStaker(address _staker) external {
        
        require(
            msg.sender == STAKE_TRANSFORMER ,
            'GRISE: wrong transformer'
        );
        
        isStaker[_staker] = false;
    }

    function getTransfee(uint256 week) external view returns (uint256) {
        return (sellTranscFee[week]);
    }
    
    function viewTokenHolderTranscReward(uint256 week) external view returns (uint256){
        return (tokenHolderReward[week].mul(_balances[msg.sender]).div(totalToken[week]));   
    }
    
    function claimTokenHolderTranscReward(uint256 week) external returns (bool){
        
        require(
            (currentGriseDay() % 7) == 0,
            'GRISE - Transcation Reward window is not yeat open'
        );
        
        require(
            week == currentGriseWeek(),
            'GRISE - You are late/early to claim reward'
        );
        
        require( 
            !isTranscFeeClaimed[msg.sender][week],
            'GRISE - Transcation Reward is already been claimed'
        );
        
        require( 
            balanceOf(msg.sender) > 0,
            'GRISE - Token holder doesnot enough balance to claim reward'
        );

        uint256 rewardAmount = tokenHolderReward[week]
                                        .mul(_balances[msg.sender])
                                        .div(totalToken[week]);
                                        
        _mint(
            msg.sender,
            rewardAmount
        );
        
        isTranscFeeClaimed[msg.sender][week] = true;

        TranscFeeClaimed(msg.sender, week, rewardAmount);
        return true;
    }
        
    function updateStakedToken(uint256 _stakedToken) external {
        
        require(
            msg.sender == STAKE_TRANSFORMER ,
            'GRISE: wrong transformer'
        );
        
        stakedToken = _stakedToken;
        totalToken[currentGriseWeek()] = _totalSupply.add(stakedToken);
    }
}
