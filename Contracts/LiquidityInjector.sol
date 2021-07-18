//SPDX-License-Identifier: MIT
pragma solidity =0.6.6;

import "./Ownable.sol";
import "./IBEP20.sol";
import "./ILIQ.sol";
import "./SafeMath.sol";
import "./SafeBEP20.sol";

contract PancakeLiquidityInjection is Ownable{
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;
    
    IBEP20 internal RBX;
    IBEP20 internal wBNB;
    IPancakeRouter01 internal LIQ;
    IBEP20 internal PancakeSwapLP;
    uint256 lockDeadline;
    address internal wBNB2;
    address internal RBX2;
    address internal LIQ2;
    bool internal LiqLocked;
    
    uint256 public Price = 477611940298500;
    
    event InjectLiquidity(uint256 amountBNB, uint256 amountRBX);
    event approveTokens(address indexed);
    event LockLiquitidy(IBEP20 LpToken, uint256 UnlockTimeStamp);
    event withDrawLpTokens();
    
    constructor(IBEP20 _wBNB, address _wBNB2, IBEP20 _RBX, address _RBX2, address _LIQ2, IPancakeRouter01 _LIQ ) public {
        wBNB = _wBNB;
        RBX = _RBX;
        RBX2 = _RBX2;
        wBNB2 = _wBNB2;
        LIQ = _LIQ;
        LIQ2 = _LIQ2;
    }
    
    function approve() public {
        RBX.safeApprove(LIQ2, 1000000000 * 10**18);
        wBNB.safeApprove(LIQ2, 1000000000 * 10**18);
        emit approveTokens(msg.sender);
    }
    
    function inject(uint256 A, uint256 B) external returns (uint amountA, uint amountB, uint liquidity) {
        uint RBXToAdd = caclulateLiquidity(A, B);
        uint wBNBToAdd = wBNB.balanceOf(address(this));
        LIQ.addLiquidity(wBNB2, RBX2, wBNBToAdd, RBXToAdd.sub(10), wBNBToAdd.sub(10), RBXToAdd, address(this), now.add(500));
        emit InjectLiquidity(wBNBToAdd, RBXToAdd);
    }
    
    function lockLiquitidy(IBEP20 pLP) public onlyOwner{
        require(LiqLocked != true);
        PancakeSwapLP = pLP;
        lockDeadline = now.add(157680000); // 5 Years
        LiqLocked = true;
        emit LockLiquitidy(PancakeSwapLP, lockDeadline);
    }
    
    function withDrawLp() public onlyOwner {
        require(lockDeadline < now);
        PancakeSwapLP.safeTransfer(msg.sender, PancakeSwapLP.balanceOf(address(this)));
        LiqLocked = false;
        emit withDrawLpTokens();
    }
    
    
    function caclulateLiquidity(uint256 reserveA, uint256 reserveB) public view returns(uint256) {
       uint256 AmountA = wBNB.balanceOf(address(this));
       if(reserveB > 0 && reserveA > 0) {
         return  AmountA.mul(reserveB) / reserveA;
       } else return AmountA.div(Price) * 10**18;
    }
    
}