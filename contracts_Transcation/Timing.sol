// SPDX-License-Identifier: --🦉--

pragma solidity =0.7.6;

import "./Declaration.sol";

abstract contract Timing is Declaration {

    function currentLPDay() public view returns (uint64) {
        return _getNow() >= LAUNCH_TIME ? _currentLPDay() : 0;
    } 

    function _currentLPDay() internal view returns (uint64) {
        return _LPDayFromStamp(_getNow());
    }

    function _LPDayFromStamp(uint256 _timestamp) internal view returns (uint64) {
        return uint64((_timestamp - LAUNCH_TIME) / SECONDS_IN_DAY_LP);
    }

    function currentGriseWeek() public view returns (uint256) {
        uint256 curGriseDay = currentGriseDay();
        return((curGriseDay % 7) > 0)? (curGriseDay / 7) + 1 : (curGriseDay / 7);
    }

    function currentGriseDay() public view returns (uint64) {
        return _getNow() >= LAUNCH_TIME ? _currentGriseDay() : 0;
    }

    function _currentGriseDay() internal view returns (uint64) {
        return _griseDayFromStamp(_getNow());
    }

    function _nextGriseDay() internal view returns (uint64) {
        return _currentGriseDay() + 1;
    }

    function _previousGriseDay() internal view returns (uint64) {
        return _currentGriseDay() - 1;
    }

    function _griseDayFromStamp(uint256 _timestamp) internal view returns (uint64) {
        return uint64((_timestamp - LAUNCH_TIME) / SECONDS_IN_DAY);
    }

    function _getNow() internal view returns (uint256) {
        return block.timestamp;
    }
}