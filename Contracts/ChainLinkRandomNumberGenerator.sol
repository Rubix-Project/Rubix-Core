pragma solidity 0.6.6;

import "./VRFConsumerBase.sol";
import "./SafeMath.sol";
import "./Ownable.sol";


contract RandomNumberConsumer is VRFConsumerBase, Ownable {
    
    event AddedToWhitelist(address indexed whitelistedAddr);
    
    bytes32 internal keyHash;
    uint256 internal fee;
    uint256[] public RANDOM_NUMBERS;
    
    uint256 public randomResult;
    
    mapping(address => bool) private whitelist;
    
    modifier restricted() {
        require(isWhitelisted(msg.sender));
        _;
    }
    

    constructor() 
        VRFConsumerBase(
            0xa555fC018435bef5A13C6c6870a9d4C11DEC329C, // VRF Coordinator
            0x84b9B910527Ad5C03A9Ca831909E21e236EA7b06  // LINK Token
        ) public
    {
        keyHash = 0xcaf3c3727e033261d383b315559476f48034c13b18f8cafed4d871abe5049186;
        fee = 0.1 * 10 ** 18; // 0.1 LINK (Varies by network)
    }
    

    
    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }

    function addToWhitelist(address _address) public onlyOwner {
        whitelist[_address] = true;
        emit AddedToWhitelist(_address);
    }    
    
    /** 
     * Requests randomness 
     */
    function getRandomNumber() public restricted returns (bytes32 requestId) {
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK - fill contract with faucet");
        return requestRandomness(keyHash, fee);
    }
    
    function testRandomness(uint256 c) public view returns(uint256) {
       uint256 x = RANDOM_NUMBERS[c];
       return x;
    }

    
    function returnRandomness() public view returns(uint256) {
        return randomResult;
    }

    /**
     * Callback function used by VRF Coordinator
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        randomResult = randomness;
    }

    // function withdrawLink() external {} - Implement a withdraw function to avoid locking your LINK in the contract
}