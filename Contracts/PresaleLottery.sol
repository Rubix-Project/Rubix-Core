//SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./Ownable.sol";
import "./IBEP20.sol";
import "./SafeMath.sol";
import "./IVRF.sol";
import "./SafeBEP20.sol";

contract ITOLotterry is Ownable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;
    
    //Interfaces 
    IVRF internal VRF; // Random Number Generator
    IBEP20 internal RBX; // Rubix Token
    IBEP20 internal wBNB; // wBNB Interace
    address payable public immutable wBNBaddress;
    
    uint256 constant GOAL = 1500;
    uint256 constant RBX_PER_TICKET = 67 * 10**18;
    
    uint256 constant MIN_REWARD = 12 * 10**18;
    
    uint256 public _TICKETS_PURCHASED;
    
    uint256 private TICKET_FEE = 0.032 * 10**18;
    
    uint256 private deadline = now.add(80); // 14 days
    
    uint256[] public winners;
    
    bool private success;
    
    mapping(uint256 => NUMBERS) private WINNING_NUMBERS;
        struct NUMBERS {
            uint256[19] _NUMBERS;
        }
        
    mapping(address => uint256) private balanceReward;
    
    mapping(address => uint256) private balanceRbx;

    mapping(uint256 => TICKET) private TICKETS;
        struct TICKET {
        address payable pAddress;
        uint256 TICKETS_PURCHASED;
        uint8 isWINNER;
    }
    
    event ContributeToPresale(address indexed Contributor, uint256 Amount);
    event DrawWinners(address indexed Callee, uint256 TimeStamp);
    event ClaimRBX(address indexed Claimer, uint256 Amount);
    event ClaimReward(address indexed Claimer, uint256 Amount);
    
    // Stores data about every player
    address[] private _PLAYERS;
        

    receive() external payable {
        require(msg.sender == wBNBaddress, "wBNB ONLY!");
    }
    
    constructor(
        address payable _wBNBAddress,
        IVRF _VRF,
        IBEP20 _RBX,
        IBEP20 _wBNB
    ) public {
        VRF = _VRF;
        wBNBaddress = _wBNBAddress;
        RBX = _RBX;
        wBNB = _wBNB;
    }
    
    /* CONTRIBUTE FUNCTION */
    
    function Contribute(uint256 TICKETS_QTY) public payable {
        require(TICKETS_QTY < 100, "RBX: Maximum limit reached");
        require(TICKETS[_TICKETS_PURCHASED].TICKETS_PURCHASED <= 100, "RBX: Maximum limit reached");
        require(_TICKETS_PURCHASED.add(TICKETS_QTY) <= 15000, "RBX: Please select another number");
        if(msg.value > 0) {
            require(msg.value >= TICKET_FEE.mul(TICKETS_QTY), "RBX: Incorrect Value");
            wrapBNB();
        }
        
        if(msg.value == 0) {
            wBNB.safeTransferFrom(msg.sender, address(this), TICKETS_QTY.mul(TICKETS_QTY));
        }
        for (uint256 i = _TICKETS_PURCHASED; i <= _TICKETS_PURCHASED.add(TICKETS_QTY - 1); i++) {
            
            TICKETS[i] = TICKET(
                _msgSender(),
                TICKETS_QTY,
                0
            );
        }
       balanceRbx[msg.sender] = balanceRbx[msg.sender].add(TICKETS_QTY.mul(RBX_PER_TICKET));    
       _TICKETS_PURCHASED = _TICKETS_PURCHASED.add(TICKETS_QTY);
       
       emit ContributeToPresale(msg.sender, TICKETS_QTY.mul(RBX_PER_TICKET));
        
    }

    /* END CONTRIBUTE FUNCTION */

 

     /* DRAW FUNCTION */
    
    function draw() public {
        require(deadline < now && _TICKETS_PURCHASED > 50, "RBX: Lottery is not concluded");
        require(VRF.returnRandomness() > 0, "RBX: Randomness is not generated!");
        
        uint256[] memory _Random = expand(VRF.returnRandomness(), 19);
        uint256 FinalMinReward;
        if(_TICKETS_PURCHASED <= 300) {
          FinalMinReward  = MIN_REWARD; 
        } else {
        uint256 A = MIN_REWARD;
        
        uint256 B = _TICKETS_PURCHASED.div(300);
        uint256 C =  A.mul(B);
        
        FinalMinReward = C; 
        }
        
        
        
        for(uint i = 0; i < 19; i++) {
            uint x = _Random[i] % _TICKETS_PURCHASED;
            WINNING_NUMBERS[0]._NUMBERS[i] = x;
            TICKETS[x].isWINNER = 1;
            if(x == 0) {
             balanceReward[TICKETS[x].pAddress] = balanceReward[TICKETS[x].pAddress].add(FinalMinReward);
            } if(x >= 1) {
            balanceReward[TICKETS[x].pAddress] = balanceReward[TICKETS[x].pAddress].add(FinalMinReward.mul(i));
        }
            emit DrawWinners(msg.sender, now);
        }
    }
    
    /* DRAW FUNCTION */
    
    

    /* CLAIM FUNCTIONS */
    function claim() public returns(bool){
        require(deadline < now && _TICKETS_PURCHASED > 50, "RBX: Lottery is not concluded");
        require(balanceRbx[msg.sender] > 0);
        
        uint256 amount = balanceReward[msg.sender];
        
        RBX.safeTransfer(msg.sender, balanceRbx[msg.sender]);
        
        balanceRbx[msg.sender] = 0;
        emit ClaimReward(msg.sender, amount);
        return(true);
    }
    
    function claimReward() public returns(bool){
        require(deadline < now && _TICKETS_PURCHASED > 50, "RBX: Lottery is not concluded");
        require(balanceReward[msg.sender] > 0);
        uint256 amount = balanceRbx[msg.sender];
        
        RBX.safeTransfer(msg.sender, balanceReward[msg.sender]);
        balanceReward[msg.sender] = 0;
        emit ClaimRBX(msg.sender, amount);
        return true;
    }

    /* END CLAIM FUNCTIONS */

 

    /* RANDOM NUMBERS */
    function requestRandomNumber() public onlyOwner {
        VRF.getRandomNumber();
    }
    
    function expand(uint256 randomValue, uint256 n)
        private
        pure
        returns (uint256[] memory expandedValues)
    {
        expandedValues = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            expandedValues[i] = uint256(keccak256(abi.encode(randomValue, i)));
        }
        return expandedValues;
    }
    /* END RANDOM NUMBERS */


 

    function wrapBNB() public payable {
        require(msg.value > 0);
        IBEP20(wBNBaddress).deposit{value: msg.value}();
        IBEP20(wBNBaddress).transfer(
            address(this),
            msg.value
        );
    }

    /* VIEW FUNCTIONS */
    function getWinningNumbers() public view returns(uint[19] memory) {
        uint[19] memory x = WINNING_NUMBERS[0]._NUMBERS;
        
        return x;
    }

    /* END VIEW FUNCTION */


}