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
            uint8(newStake.stakeType),
            newStake.stakedAmount,
            newStake.stakesShares
        );
        
        _addScheduledShares(
            newStake.finalDay,
            newStake.stakesShares
        );

        GRISE_CONTRACT.setStaker(msg.sender);
        GRISE_CONTRACT.updateStakedToken(globals.totalStaked);

        if (newStake.stakeType != StakeType.SHORT_TERM) {
            GRISE_CONTRACT.updateMedTermShares(globals.mediumTermShares);
        }
        
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
            uint256 _startDay
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
            uint8(endedStake.stakeType),
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
        
        GRISE_CONTRACT.resetStaker(msg.sender);
        GRISE_CONTRACT.updateStakedToken(globals.totalStaked);

        if (endedStake.stakeType != StakeType.SHORT_TERM) {
            GRISE_CONTRACT.updateMedTermShares(globals.mediumTermShares);
        }
        
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
            'GRISE: Not an active stake'
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
            uint256 remainingDays
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

        scrapeAmount = getTranscRewardAmount(_stakeID);

        scrapeAmount += getPenaltyRewardAmount(_stakeID);

        scrapeAmount += getReservoirRewardAmount(_stakeID);

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
        uint64 startDay,
        uint64 lockDays,
        uint64 finalDay,
        uint64 closeDay,
        // uint64 scrapeDay,
        uint256 stakedAmount,
        uint256 transcRewardAmount,
        uint256 penaltyRewardAmount,
        uint256 reservoirRewardAmount,
        uint256 penaltyAmount,
        bool isActive,
        bool isMature
    )
    {
        Stake memory stake = stakes[_staker][_stakeID];
        startDay = uint64(stake.startDay);
        lockDays = uint64(stake.lockDays);
        finalDay = uint64(stake.finalDay);
        closeDay = uint64(stake.closeDay);
        // scrapeDay = uint64(stake.scrapeDay);
        stakedAmount = stake.stakedAmount;
        transcRewardAmount = getTranscRewardAmount(_stakeID);
        penaltyRewardAmount = getPenaltyRewardAmount(_stakeID);
        reservoirRewardAmount = getReservoirRewardAmount(_stakeID);
        penaltyAmount = _calculatePenaltyAmount(stake);
        isActive = stake.isActive;
        isMature = _isMatureStake(stake);
    }

    function getRewardScarpeDay(
        address _staker,
        bytes16 _stakeID
    )
    external
    view
    returns (
        uint64 scrapeDay
    )
    {
        Stake memory stake = stakes[_staker][_stakeID];
        scrapeDay = uint64(stake.scrapeDay);
    }

    function getTranscRewardAmount(bytes16 _stakeID) public view returns (uint256 rewardAmount) {
        Stake memory _stake = stakes[msg.sender][_stakeID];

        if ( _stakeEligibleForWeeklyReward(_stake))
        {
            uint256 _endDay = currentGriseDay().sub(currentGriseDay().mod(GRISE_WEEK));

            rewardAmount = _loopTranscRewardAmount(
                _stake.stakesShares,
                _startingDay(_stake),
                _endDay,
                _stake.stakeType);
        }
    }

    function getPenaltyRewardAmount(bytes16 _stakeID) public view returns (uint256 rewardAmount) {
        Stake memory _stake = stakes[msg.sender][_stakeID];

        if ( _stakeEligibleForWeeklyReward(_stake))
        {
            uint256 _endDay = currentGriseDay().sub(currentGriseDay().mod(GRISE_WEEK));

            rewardAmount = _loopPenaltyRewardAmount(
                _stake.stakesShares,
                _startingDay(_stake),
                _endDay,
                _stake.stakeType);
        }
    }

    function getReservoirRewardAmount(bytes16 _stakeID) public view returns (uint256 rewardAmount) {
        Stake memory _stake = stakes[msg.sender][_stakeID];

        if ( _stakeEligibleForMonthlyReward(_stake))
        {
            uint256 _endDay = currentGriseDay().sub(currentGriseDay().mod(GRISE_MONTH));

            rewardAmount = _loopReservoirRewardAmount(
                _stake.stakesShares,
                _startingDay(_stake),
                _endDay
            );
        }
    }

    function getInflationRewardAmount(bytes16 _stakeID) public view returns (uint256 rewardAmount) {
        Stake memory _stake = stakes[msg.sender][_stakeID];

        if ( _stake.isActive && !_stakeNotStarted(_stake))
        {
            rewardAmount = _loopInflationRewardAmount(
            _stake.stakesShares,
            _stake.startDay,
            currentGriseDay(),
            _stake.stakeType);
        }
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

    function _storePenalty(
        uint256 _storeDay,
        uint256 _penalty
    )
        private
    {
        if (_penalty > 0) {
            totalPenalties[_storeDay] =
            totalPenalties[_storeDay].add(_penalty);

            MLTPenaltiesRewardPerShares[_storeDay] += 
                _penalty.mul(MED_LONG_STAKER_PENALTY_REWARD)
                        .div(REWARD_PRECISION_RATE)
                        .div(globals.mediumTermShares);

            STPenaltiesRewardPerShares[_storeDay] +=
                _penalty.mul(SHORT_STAKER_PENALTY_REWARD)
                        .div(REWARD_PRECISION_RATE)
                        .div(globals.shortTermShares);

            ReservoirPenaltiesRewardPerShares[_storeDay] +=
                _penalty.mul(RESERVOIR_PENALTY_REWARD)
                        .div(REWARD_PRECISION_RATE)
                        .div(globals.mediumTermShares);

            GRISE_CONTRACT.mintSupply(
                TEAM_ADDRESS,
                _penalty.mul(TEAM_PENALTY_REWARD)
                        .div(REWARD_PRECISION_RATE)
            );
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

        _rewardAmount = _loopPenaltyRewardAmount(
            _stake.stakesShares,
            _startingDay(_stake),
            _calculationDay(_stake),
            _stake.stakeType
        );

        _rewardAmount += _loopTranscRewardAmount(
            _stake.stakesShares,
            _startingDay(_stake),
            _calculationDay(_stake),
            _stake.stakeType
        );

        _rewardAmount += _loopReservoirRewardAmount(
            _stake.stakesShares,
            _startingDay(_stake),
            _calculationDay(_stake)
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
        for (uint256 day = _startDay; day < _finalDay; day++) 
        {
            if (_stakeType == StakeType.SHORT_TERM)
            {
                _rewardAmount += STPenaltiesRewardPerShares[day]
                                    .mul(_stakeShares);
            } else {
                _rewardAmount += MLTPenaltiesRewardPerShares[day]
                                    .mul(_stakeShares);
            }
        }
    }

    function _loopReservoirRewardAmount(
        uint256 _stakeShares,
        uint256 _startDay,
        uint256 _finalDay
    )
        private
        view
        returns (uint256 _rewardAmount)
    {
        
        for (uint256 day = _startDay; day < _finalDay; day++) 
        {
            _rewardAmount = 
            _rewardAmount.add(ReservoirPenaltiesRewardPerShares[day]);
        }

        _rewardAmount = 
        _rewardAmount.add(GRISE_CONTRACT.getReservoirReward(_startDay, _finalDay));

        _rewardAmount = 
        _rewardAmount.mul(_stakeShares);
    }

    function _loopTranscRewardAmount(
        uint256 _stakeShares,
        uint256 _startDay,
        uint256 _finalDay,
        StakeType _stakeType
    )
        private
        view
        returns (uint256 _rewardAmount)
    {
        uint256 stakedAmount = _stakeShares.mul(globals.sharePrice);
        
        if (_stakeType != StakeType.SHORT_TERM)
        {
            _rewardAmount =
            _rewardAmount.add(GRISE_CONTRACT.getTransFeeReward(_startDay, _finalDay))
                          .mul(_stakeShares); 
        }

        _rewardAmount =
        _rewardAmount.add(GRISE_CONTRACT.getTokenHolderReward(_startDay, _finalDay))
                     .mul(stakedAmount);
    }

    function getShortTermSlotLeft() external view returns (uint256) {
        return stakeCaps[StakeType.SHORT_TERM][0].maxStakingSlot
                .sub(stakeCaps[StakeType.SHORT_TERM][0].stakingSlotCount);
    }

    function getLargeTermSlotLeft() external view returns (uint256) {
        return stakeCaps[StakeType.LARGE_TERM][0].maxStakingSlot
                .sub(stakeCaps[StakeType.LARGE_TERM][0].stakingSlotCount);
    }

    function getMediumTermSlotLeft() external view returns (uint256, uint256, uint256) {
        return ( stakeCaps[StakeType.MEDIUM_TERM][0].maxStakingSlot
                    .sub(stakeCaps[StakeType.MEDIUM_TERM][0].stakingSlotCount),
                 stakeCaps[StakeType.MEDIUM_TERM][1].maxStakingSlot
                    .sub(stakeCaps[StakeType.MEDIUM_TERM][1].stakingSlotCount),
                stakeCaps[StakeType.MEDIUM_TERM][2].maxStakingSlot
                    .sub(stakeCaps[StakeType.MEDIUM_TERM][2].stakingSlotCount));
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