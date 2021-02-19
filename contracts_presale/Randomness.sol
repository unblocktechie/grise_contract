// SPDX-License-Identifier: --🦉--
pragma solidity =0.7.6;

import "./nreAPI.sol";

contract Randomness is usingNRE {
    uint256 public randomNumber;    
    
   function stateRandomNumber() public {
       randomNumber = (rm()%(10**5));
      //randomNumber = (((rv()%10)*10000)+((rd()%10)*1000)+((rf()%10)*100)+((rx()%10)*10)+(rm()%10));
   }
 
}