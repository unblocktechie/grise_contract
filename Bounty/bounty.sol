// SPDX-License-Identifier: --🦉--

pragma solidity ^0.7.6;

contract Bounty {
    event Deposit(address indexed sender, uint amount, uint balance);
    event credit(address indexed sender, uint amount);

    address private owner;
    mapping(address => bool) public bountyUser;
    uint256 public numOfBounty;
    uint256 private rewardPerBounty;
    uint256 public rewardAmount;

    modifier onlyOwner() {
        require(owner == msg.sender, "not owner");
        _;
    }

    constructor(){
        owner = msg.sender;   
    }

    function setContractGateKeeper(
        address getKeeper
    )
        external
        onlyOwner
    {
        owner = getKeeper;
    }

    receive() payable external {}
    
    fallback() payable external
    {
        rewardAmount += msg.value;
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function rewardDivider(
        uint256 NoOfBountyUser
    )
        external
        onlyOwner
        returns (uint256)
    {
        require(NoOfBountyUser > 0, "NoOfBountyUser should be non-zero");

        rewardPerBounty = rewardAmount / NoOfBountyUser;
        numOfBounty = NoOfBountyUser;
        return rewardPerBounty;
    }

    function sendReward(
        address[] memory _bountyUsers
    )
        external
        payable
        onlyOwner
    {
        require(_bountyUsers.length > 0, "bountyUsers required");

        for (uint i = 0; i < _bountyUsers.length; i++) {
            address bounty = _bountyUsers[i];

            require(bounty != address(0x0), "invalid bounty");
            require(numOfBounty > 0 && 
                    address(this).balance >= rewardPerBounty,
                    "All Bounty Reward Claimed");

            if (bountyUser[bounty] && 
                    !notContract(bounty))
            {
                continue;   
            }

            bountyUser[bounty] = true;
            numOfBounty--;

            (bool success, ) = bounty.call{value: rewardPerBounty}("Grise Bounty Reward");

            require(success, "tx failed");
            emit credit(bounty, rewardPerBounty);
        }  
    }


    function rewardAmountInContract()
        external
        view
        returns (uint256)
    {
        return (address(this).balance);   
    }

    function transferPendingReward(uint _amount)
        external
        payable
        onlyOwner
        returns (uint256 amount)
    {
        amount = (_amount > 0) ?
                            _amount:
                            address(this).balance;

        (bool success, ) = owner.call{ value: amount}("Pending Bounty Amount");

        require(success, "tx failed");

        emit credit(owner, amount);
    }

    function notContract(address _addr) internal view returns (bool) {
        uint32 size;
        assembly {
            size := extcodesize(_addr)
        }
        return (size == 0);
    }
}
