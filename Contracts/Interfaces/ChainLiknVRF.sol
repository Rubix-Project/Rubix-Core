pragma solidity ^0.6.0;

interface IVRF {
    function getRandomNumber() external;
    
    function returnRandomness() external view returns(uint256);
    
    function expand(uint256 randomValue, uint256 n) external view returns(uint[] memory);
}