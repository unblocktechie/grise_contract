// SPDX-License-Identifier: --🦉--

pragma solidity =0.7.6;

import "./Snapshot.sol";

contract StakingToken is Snapshot {

    using SafeMath for uint256;

    /**
     * @notice ability to define Grise contract
     * @dev this method renounce griseGateKeeper access
     * @param _immutableAddress contract address
     */
    function setGriseAddress(
        address _immutableAddress
    )
        external
    {
        require(
            griseGateKeeper == msg.sender,
            'GRISE: griseGateKeeper is undefined'
        );
        GRISE_CONTRACT = IGriseToken(_immutableAddress);
        griseGateKeeper = address(0x0);
    }

   /**
     * @notice allows to create stake directly with ETH
     * if you don't have GRISE tokens method will convert
     * and use amount returned from UNISWAP to open a stake
     * @param _lockDays amount of days it is locked for.
     */
    function createStakeWithETH(
        StakeType _stakeType,
        uint64 _lockDays
    )
        external
        payable
        returns (bytes16, uint256)
    {
        address[] memory path = new address[](2);
            path[0] = WETH;
            path[1] = address(GRISE_CONTRACT);

        uint256[] memory amounts =
        UNISWAP_ROUTER.swapExactETHForTokens{value: msg.value}(
            1,
            path,
            msg.sender,
            block.timestamp + 2 hours
        );

        return createStake(
            amounts[1],
            _stakeType,
            _lockDays
        );
    }
    
    /**
     * @notice A method for a staker to create a stake
     * @param _stakedAmount amount of GRISE staked.
     * @param _stakeType Small/Medium/Large.
     * @param _lockDays amount of days it is locked for.
     */
    function createStake(
        uint256 _stakedAmount,
        StakeType _stakeType,
        uint64 _lockDays
    )
        snapshotTrigger
        public
        returns (bytes16, uint256)
    {
        // stakingSlot will be 0 for short/long term staking and
        // stakingSlot will be 0,1,2 for 3,6,9 month medium term staking respectively.
        uint8 stakingSlot; 

        if (_stakeType == StakeType.MEDIUM_TERM){
            if (_lockDays == 168){ // 6 Month
                stakingSlot = 1;
            } else if (_lockDays == 252){ // 9 Month
                stakingSlot = 2;
            }
        }

        require(
            _lockDays >= stakeDayLimit[_stakeType].minStakeDay &&
            _lockDays <= stakeDayLimit[_stakeType].maxStakeDay,
            'GRISE: stake is not in range'
        );

        require(
            _stakedAmount >= stakeCaps[_stakeType][stakingSlot].minStakingAmount,
            'GRISE: stake is not large enough'
        );

        require(
            stakeCaps[_stakeType][stakingSlot].stakingSlotCount <= 
                    stakeCaps[_stakeType][stakingSlot].maxStakingSlot ,
            'GRISE: All staking slot is occupied not extra slot is available'
        );

        uint64 newOccupiedSlotCount = _stakedAmount
                                      .mod(stakeCaps[_stakeType][stakingSlot].minStakingAmount) != 0?
                                      uint64(_stakedAmount
                                      .div(stakeCaps[_stakeType][stakingSlot].minStakingAmount) + 1) :
                                      uint64(_stakedAmount
                                      .div(stakeCaps[_stakeType][stakingSlot].minStakingAmount));

        require(
            (stakeCaps[_stakeType][stakingSlot].stakingSlotCount + newOccupiedSlotCount <= 
                    stakeCaps[_stakeType][stakingSlot].maxStakingSlot),
            'GRISE: All staking slot is occupied not extra slot is available'
        );

        stakeCaps[_stakeType][stakingSlot].stakingSlotCount = 
        stakeCaps[_stakeType][stakingSlot].stakingSlotCount.add(newOccupiedSlotCount);

        (
            Stake memory newStake,
            bytes16 stakeID,
            uint256 _startDay
        ) =

        _createStake(msg.sender, _stakedAmount, _lockDays, _stakeType, newOccupiedSlotCount);

        stakes[msg.sender][stakeID] = newStake;

        _increaseStakeCount(
            msg.sender
        );

        _increaseGlobals(
            newStake.stakedAmount,
            newStake.stakesShares
        );
        
        _addScheduledShares(
            newStake.finalDay,
            newStake.stakesShares
        );

        GRISE_CONTRACT.updateStakedToken(globals.totalStaked);
        GRISE_CONTRACT.setStaker(msg.sender);

        emit StakeStart(
            stakeID,
            msg.sender,
            uint256(newStake.stakeType),
            newStake.stakedAmount,
            newStake.stakesShares,
            newStake.startDay,
            newStake.lockDays,
            newStake.daiEquivalent
        );

        return (stakeID, _startDay);
    }

    /**
    * @notice A method for a staker to start a stake
    * @param _staker ...
    * @param _stakedAmount ...
    * @param _lockDays ...
    */
    function _createStake(
        address _staker,
        uint256 _stakedAmount,
        uint64 _lockDays,
        StakeType  _stakeType,
        uint64 _totalOccupiedSlot
    )
        private
        returns (
            Stake memory _newStake,
            bytes16 _stakeID,
            uint64 _startDay
        )
    {
        GRISE_CONTRACT.burnSupply(
            _staker,
            _stakedAmount
        );

        _startDay = currentGriseDay() + 1;
        _stakeID = generateStakeID(_staker);

        _newStake.stakeType = _stakeType;
        _newStake.totalOccupiedSlot = _totalOccupiedSlot;
        _newStake.lockDays = _lockDays;
        _newStake.startDay = _startDay;
        _newStake.finalDay = _startDay + _lockDays;
        _newStake.isActive = true;

        _newStake.stakedAmount = _stakedAmount;
        _newStake.stakesShares = _stakesShares(
            _stakedAmount,
            globals.sharePrice
        );

        _updateDaiEquivalent();

        _newStake.daiEquivalent = latestDaiEquivalent
            .mul(_newStake.stakedAmount)
            .div(REI_PER_GRISE);
    }

    /**
    * @notice A method for a staker to remove a stake
    * belonging to his address by providing ID of a stake.
    * @param _stakeID unique bytes sequence reference to the stake
    */
    function endStake(
        bytes16 _stakeID
    )
        snapshotTrigger
        external
        returns (uint256)
    {
        (
            Stake memory endedStake,
            uint256 penaltyAmount
        ) =

        _endStake(
            msg.sender,
            _stakeID
        );

        _decreaseGlobals(
            endedStake.stakedAmount,
            endedStake.stakesShares
        );

        _removeScheduledShares(
            endedStake.finalDay,
            endedStake.stakesShares
        );

        _storePenalty(
            endedStake.closeDay,
            penaltyAmount
        );

        uint8 stakingSlot; 
        if (endedStake.stakeType == StakeType.MEDIUM_TERM){
            if (endedStake.lockDays == 168) { // 6 Month
                stakingSlot = 1;
            } else if (endedStake.lockDays == 252) { // 9 Month
                stakingSlot = 2;
            }
        }

        stakeCaps[endedStake.stakeType][stakingSlot].stakingSlotCount = 
        stakeCaps[endedStake.stakeType][stakingSlot].stakingSlotCount.sub(endedStake.totalOccupiedSlot);
        
        GRISE_CONTRACT.updateStakedToken(globals.totalStaked);
        GRISE_CONTRACT.resetStaker(msg.sender);
        
        emit StakeEnd(
            _stakeID,
            msg.sender,
            uint256(endedStake.stakeType),
            endedStake.stakedAmount,
            endedStake.stakesShares,
            endedStake.rewardAmount,
            endedStake.closeDay,
            penaltyAmount
        );

        return endedStake.rewardAmount;
    }

    function _endStake(
        address _staker,
        bytes16 _stakeID
    )
        private
        returns (
            Stake storage _stake,
            uint256 _penalty
        )
    {
        require(
            stakes[_staker][_stakeID].isActive,
            'GRISE: not an active stake'
        );

        _stake = stakes[_staker][_stakeID];
        _stake.closeDay = currentGriseDay();
        _stake.rewardAmount = _calculateRewardAmount(_stake);
        _penalty = _calculatePenaltyAmount(_stake);

        _stake.isActive = false;

        GRISE_CONTRACT.mintSupply(
            _staker,
            _stake.stakedAmount > _penalty ?
            _stake.stakedAmount - _penalty : 0
        );

        GRISE_CONTRACT.mintSupply(
            _staker,
            _stake.rewardAmount
        );
    }

    /**
    * @notice alloes to scrape Reward from active stake
    * @param _stakeID unique bytes sequence reference to the stake
    */
    function scrapeReward(
        bytes16 _stakeID
    )
        external
        snapshotTrigger
        returns (
            uint256 scrapeDay,
            uint256 scrapeAmount,
            uint256 remainingDays,
            uint256 stakersPenalty
        )
    {
        require(
            stakes[msg.sender][_stakeID].isActive,
            'GRISE: Not an active stake'
        );

        Stake memory stake = stakes[msg.sender][_stakeID];

        require(
            (globals.currentGriseDay
                    .sub(stake.startDay)
                    .div(GRISE_WEEK)) > 0,
            'GRISE: Stake is not yet mature to claim Reward'
        );

        scrapeDay = _calculationDay(stake);

        scrapeDay = scrapeDay < stake.finalDay
            ? scrapeDay.sub(scrapeDay.mod(GRISE_WEEK))
            : scrapeDay;

        scrapeAmount = _loopPanaltyRewardAmount(
            stake.stakesShares,
            _startingDay(stake),
            scrapeDay,
            stake.stakeType
        );

        remainingDays = _daysLeft(stake);
        scrapes[msg.sender][_stakeID] =
        scrapes[msg.sender][_stakeID].add(scrapeAmount);
        
        stake.scrapeDay = scrapeDay;
        stakes[msg.sender][_stakeID] = stake;

        GRISE_CONTRACT.mintSupply(
            msg.sender,
            scrapeAmount
        );

        emit InterestScraped(
            _stakeID,
            msg.sender,
            scrapeAmount,
            scrapeDay,
            currentGriseDay()
        );
    }

    function _addScheduledShares(
        uint256 _finalDay,
        uint256 _shares
    )
        internal
    {
        scheduledToEnd[_finalDay] =
        scheduledToEnd[_finalDay].add(_shares);
    }

    function _removeScheduledShares(
        uint256 _finalDay,
        uint256 _shares
    )
        internal
    {
        if (_notPast(_finalDay)) {

            scheduledToEnd[_finalDay] =
            scheduledToEnd[_finalDay] > _shares ?
            scheduledToEnd[_finalDay] - _shares : 0;

        } else {

            uint256 _day = currentGriseDay() - 1;
            snapshots[_day].scheduledToEnd =
            snapshots[_day].scheduledToEnd > _shares ?
            snapshots[_day].scheduledToEnd - _shares : 0;
        }
    }

    function checkMatureStake(
        address _staker,
        bytes16 _stakeID
    )
        external
        view
        returns (bool isMature)
    {
        Stake memory stake = stakes[_staker][_stakeID];
        isMature = _isMatureStake(stake);
    }

    function checkStakeByID(
        address _staker,
        bytes16 _stakeID
    )
        external
        view
        returns (
            uint256 startDay,
            uint256 lockDays,
            uint256 finalDay,
            uint256 closeDay,
            uint256 scrapeDay,
            uint256 stakedAmount,
            uint256 stakesShares,
            uint256 rewardAmount,
            uint256 penaltyAmount,
            bool isActive,
            bool isMature
        )
    {
        Stake memory stake = stakes[_staker][_stakeID];
        startDay = stake.startDay;
        lockDays = stake.lockDays;
        finalDay = stake.finalDay;
        closeDay = stake.closeDay;
        scrapeDay = stake.scrapeDay;
        stakedAmount = stake.stakedAmount;
        stakesShares = stake.stakesShares;
        rewardAmount = _checkRewardAmount(stake);
        penaltyAmount = _calculatePenaltyAmount(stake);
        isActive = stake.isActive;
        isMature = _isMatureStake(stake);
    }

    function _stakesShares(
        uint256 _stakedAmount,
        uint256 _sharePrice
    )
        private
        pure
        returns (uint256)
    {
        return _stakedAmount
                .div(_sharePrice);
    }

    function _checkRewardAmount(Stake memory _stake) private view returns (uint256) {
        return _stake.isActive ? _detectReward(_stake) : _stake.rewardAmount;
    }

    function _detectReward(Stake memory _stake) private view returns (uint256) {
        return _stakeNotStarted(_stake) ? 0 : _calculateRewardAmount(_stake);
    }

    function _storePenalty(
        uint64 _storeDay,
        uint256 _penalty
    )
        private
    {
        if (_penalty > 0) {
            totalPenalties[_storeDay] =
            totalPenalties[_storeDay].add(_penalty);

            totalPenaltiesPerShares[_storeDay] += 
            _penalty.div(snapshots[_storeDay].totalShares);

        }
    }

    function _calculatePenaltyAmount(
        Stake memory _stake
    )
        private
        view
        returns (uint256)
    {
        return _stakeNotStarted(_stake) || _isMatureStake(_stake) ? 0 : _getPenalties(_stake);
    }

    function _getPenalties(Stake memory _stake)
        private
        view
 
        returns (uint256)
    {
        return _stake.stakedAmount * ((PENALTY_RATE * (_daysLeft(_stake) - 1) / (_getLockDays(_stake)))) / 10000;
    }

    function _calculateRewardAmount(
        Stake memory _stake
    )
        private
        view
        returns (uint256 _rewardAmount)
    {

        _rewardAmount = _loopPanalityRewardAmount(
            _stake.stakesShares,
            _startingDay(_stake),
            _calculationDay(_stake),
            _stake.stakeType
        );

        _rewardAmount += _loopInflationRewardAmount(
            _stake.stakesShares,
            _stake.startDay,
            _stake.finalDay,
            _stake.stakeType
        );
    }

    function _loopInflationRewardAmount(
        uint256 _stakeShares,
        uint256 _startDay,
        uint256 _finalDay,
        StakeType _stakeType
    )
        private
        view
        returns (uint256 _rewardAmount)
    {
        uint256 inflationAmount;
        if (_stakeType == StakeType.SHORT_TERM)
        {
            return 0;
        }

        for (uint256 _day = _startDay; _day < _finalDay; _day++) {

            inflationAmount = (_stakeType == StakeType.MEDIUM_TERM) ? 
                                snapshots[_day].inflationAmount
                                .mul(MED_TERM_INFLATION_REWARD)
                                .div(REWARD_PRECISION_RATE) :
                                snapshots[_day].inflationAmount
                                .mul(LONG_TERM_INFLATION_REWARD)
                                .div(REWARD_PRECISION_RATE);

            _rewardAmount += _stakeShares * PRECISION_RATE / inflationAmount;
        }
    }

    function _loopPenaltyRewardAmount(
        uint256 _stakeShares,
        uint256 _startDay,
        uint256 _finalDay,
        StakeType _stakeType
    )
        private
        view
        returns (uint256 _rewardAmount)
    {
        uint16 rewardRate = MED_LONG_STAKER_PENALTY_REWARD;

        if (_stakeType == StakeType.SHORT_TERM)
        {
            rewardRate = SHORT_STAKER_PENALTY_REWARD;
        }
        
        for (uint256 _day = _startDay; _day < _finalDay; _day++) 
        {
            _rewardAmount += totalPenaltiesPerShares[_day].mul(rewardRate)
                                                  .div(REWARD_PRECISION_RATE)
                                                  .mul(_stakeShares);

        }
    }

    function _updateDaiEquivalent()
    internal
    returns (uint256)
    {
        try UNISWAP_ROUTER.getAmountsOut(
            REI_PER_GRISE, _path
        ) returns (uint256[] memory results) {
            latestDaiEquivalent = results[2];
            return latestDaiEquivalent;
        } catch Error(string memory) {
            return latestDaiEquivalent;
        } catch (bytes memory) {
            return latestDaiEquivalent;
        }
    }
}