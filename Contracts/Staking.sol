pragma solidity ^0.6.0;

import "./SafeMath.sol";
import "./SafeBEP20.sol";
import "./Ownable.sol";

// SPDX-License-Identifier: MIT

// This smart contract was designed by the Rubix project and is not intended to be copied or manipulated without Rubix's dev's written permission.

// Website: https://rubix.onl
// Twitter: https://twitter.com/rubix0x

// The purpose of this contract is to provide Rubix token holders an opportunity to stake their tokens for a reward in return.

// This contract is also able to receive and distribute wBNB to RBX stakeholders.

// Warning! This contract has not been audited. Use at your own risk.

// We trust our code is good.

contract FelxibleStaking is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    event Received(address, uint256);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    // RBX Tokens
    IBEP20 private RBX;

    // BNB Token

    IBEP20 private wBNB;

    address private jackpotPool;

    // Current Pool ID
    uint256 public _poolId;

    // Base reward APY
    uint256 private yield;

    // Investors index ID
    uint256 private _investorID;

    // Total RBX staked on this contract
    uint256 private _RbxStaked;

    // Returns total BNB raised
    uint256 private _bnbFunded;

    // Sets pool Limit
    uint256 private _poolLimit;

    // Returns boolion value of pool status
    bool private _paused;

    // Sets time before first reward claim
    uint256 constant rPeriod = 60;
    uint256 constant secondsinYear = 31536000;

    event funding(address indexed depositer, uint256 RBX, uint256 _wBNB2);
    event staked(
        address indexed account,
        uint256 amount,
        uint256 ID,
        uint256 pID,
        uint256 depositTimeStamp,
        uint256 releaseTimeStamp
    );

    event withdrew(
        address indexed account,
        uint256 RBX,
        uint256 wBNB,
        uint256 ID,
        uint256 pID,
        uint256 now
    );
    event claimed(
        address indexed account,
        uint256 RBX,
        uint256 wBNB,
        uint256 ID,
        uint256 now
    );
    event stakingPaused();
    event poolUpdated();
    event updatedJackpotAddress(address indexed newJackpotAddress);
    event newRBXAPY(uint256 newAPY2);
    event AddedToWhitelist(address indexed whitelistedAddr);

    mapping(address => bool) private whitelist;

    // @Dev checks if a user is an active Stakeholder
    mapping(address => bool) private _isStakeholder;

    // @Dev Mapping for storing pool data
    mapping(uint256 => pool) private poolData;

    struct pool {
        uint256 startTS;
        uint256 endTS;
        uint256 shIndex;
        uint256 bnbFunded;
        uint256 rbxFunded;
        uint256 poolWeight;
        bool updated;
    }

    // @Dev Stores stakeholders data
    mapping(uint256 => investors) private Investors;

    struct investors {
        address payable user;
        uint256 sWeight;
        uint256 depositTS;
        uint256 joinedTS;
        uint256 releaseTS;
        uint256 rewardTS2;
        uint256 pid;
        uint256 accBNB;
        uint256 accRBX;
        uint256 accRBX2; // RBX Earned from yield staking
        bool rClaimed;
        bool claimed;
    }

    constructor(
        IBEP20 _RBX,
        IBEP20 _wBNB,
        uint256 _yield
    ) public {
        RBX = _RBX;
        wBNB = _wBNB;
        yield = _yield;
    }

    modifier restricted() {
        require(isWhitelisted(msg.sender));
        _;
    }

    function isWhitelisted(address _address) public view returns (bool) {
        return whitelist[_address];
    }

    function addToWhitelist(address _address) public onlyOwner {
        whitelist[_address] = true;
        emit AddedToWhitelist(_address);
    }

    function addJackpotAddress(address _jackpotAddress) public onlyOwner {
        jackpotPool = _jackpotAddress;
        emit updatedJackpotAddress(_jackpotAddress);
    }

    function updateAPY(uint256 newAPY) public onlyOwner {
        yield = newAPY;
        emit newRBXAPY(newAPY);
    }

    // Checks if the user is an active stakeholder

    function eligible(address userAddress) public view returns (bool) {
        return _isStakeholder[userAddress];
    }

    function topUp(uint256 value1, uint256 value2) external restricted {
        updatePool();
        poolData[_poolId].bnbFunded = poolData[_poolId].bnbFunded.add(value1);
        poolData[_poolId].rbxFunded = poolData[_poolId].rbxFunded.add(value2);
        emit funding(msg.sender, value1, value2);
    }

    function deposit(uint256 amount, uint256 time) public returns (bool) {
        require(_paused == false, "Staking is paused");
        require(
            amount <= 1500000000000000000000,
            "Total amount should be less or equal 1,500 RBX!"
        );

        require(time <= 4233600, "Time must be less than 49 days");

        updatePool();

        SafeRbxTransfer(msg.sender, amount);

        _investorID++;

        poolData[_poolId].shIndex++;

        poolData[_poolId].poolWeight = poolData[_poolId].poolWeight.add(amount);

        _RbxStaked = _RbxStaked.add(amount);

        Investors[_investorID] = investors(
            msg.sender,
            amount,
            now,
            now,
            now.add(time),
            poolData[_poolId].endTS,
            _poolId,
            0,
            0,
            0,
            false,
            false
        );

        emit staked(
            msg.sender,
            amount,
            _poolId,
            _investorID,
            now,
            now.add(time)
        );

        return true;
    }

    //Allows owner to pause staking in case of emergency
    function pauseStaking(bool pause) public onlyOwner {
        _paused = pause;
    }

    //Transfers funds
    function SafeRbxTransfer(address sender, uint256 amount)
        private
        returns (bool)
    {
        RBX.safeTransferFrom(address(sender), address(this), amount);

        return true;
    }

    function SafeBNBTransfer(address sender, uint256 amount)
        private
        returns (bool)
    {
        wBNB.safeTransferFrom(address(sender), address(this), amount);

        return true;
    }

    //Starts new pool
    function updatePool() public {
        if (poolData[_poolId].startTS == 0) {
            poolData[_poolId].startTS = now;
            poolData[_poolId].endTS = now.add(rPeriod);
            poolData[_poolId].endTS = now.add(rPeriod);
        }
        if (now >= poolData[_poolId].endTS) {
            if (poolData[_poolId].shIndex == 0) {
                poolData[_poolId].startTS = now;
                poolData[_poolId].endTS = now.add(rPeriod);
            }
            if (poolData[_poolId].shIndex > 0) {
                _poolId++;
                poolData[_poolId].startTS = now;
                poolData[_poolId].endTS = now.add(rPeriod);
                poolData[_poolId.sub(1)].updated = true;
            }
        }
        emit poolUpdated();
    }

    //Returns users share of the pool based on the staking weight.
    function pShare(uint256 shID) private view returns (uint256) {
        if (Investors[shID].claimed == true) {
            return 0;
        } else {
            return
                Investors[shID].sWeight.mul(1e12).div(
                    poolData[myPoolID(shID)].poolWeight
                );
        }
    }

    function myPoolID(uint256 shID) public view returns (uint256) {
        return Investors[shID].pid;
    }

    //Returns amount of pending BNB in real time
    function uBNBa(uint256 shID) private view returns (uint256) {
        uint256 A = poolData[myPoolID(shID)].bnbFunded.mul(pShare(shID)).div(
            1e12
        );
        uint256 B = Investors[shID].rewardTS2.sub(Investors[shID].joinedTS);
        uint256 C = A.div(rPeriod);
        uint256 D = B.mul(C);
        uint256 E = now.sub(Investors[shID].joinedTS);

        if (Investors[shID].rewardTS2 > now) {
            return C.mul(E);
        }
        if (Investors[shID].rewardTS2 < now) {
            return D;
        } else if (Investors[shID].rClaimed == true) {
            return 0;
        }
    }

    // @Dev Function returns unclaimable rewards that will be forwarded to Jackpot pool.
    function uBNBb(uint256 shID) private view returns (uint256) {
        // Returns share of the pool
        uint256 A = poolData[myPoolID(shID)].bnbFunded.mul(pShare(shID)).div(
            1e12
        );
        // Reward per second
        uint256 E = A.div(rPeriod);
        // Returns Actual reward
        uint256 F = Investors[shID].joinedTS.sub(
            poolData[myPoolID(shID)].startTS
        );
        uint256 G = F.mul(E);
        return G;
    }

    // Returns staking rewards based on the annual yield.
    function uRBXa(uint256 shID) private view returns (uint256) {
        uint256 A = Investors[shID].sWeight.mul(yield).div(100);
        uint256 B = A.div(secondsinYear);
        uint256 C = now.sub(Investors[shID].depositTS);
        uint256 D = Investors[shID].releaseTS.sub(Investors[shID].depositTS);
        if (timeLeft(shID) == true) {
            return B.mul(C).sub(Investors[shID].accRBX2);
        }
        if (timeLeft(shID) == false) {
            return B.mul(D).sub(Investors[shID].accRBX2);
        }
    }

    // @Dev: Function returns total owed claimable reward.
    function uRBXb(uint256 shID) private view returns (uint256) {
        uint256 A = poolData[myPoolID(shID)].rbxFunded.mul(pShare(shID)).div(
            1e12
        );
        uint256 B = A.div(rPeriod);
        uint256 C = Investors[shID].rewardTS2.sub(Investors[shID].joinedTS);
        uint256 D = now.sub(Investors[shID].joinedTS);
        uint256 E = B.mul(C);
        if (Investors[shID].rewardTS2 > now) {
            return B.mul(D);
        }
        if (Investors[shID].rewardTS2 < now) {
            return E;
        } else if (Investors[shID].rClaimed == true) {
            return 0;
        }
    }

    // @Dev Function returns unclaimable rewards that will be forwarded to Jackpot pool.
    function uRBXe(uint256 shID) private view returns (uint256) {
        // Returns share of the pool
        uint256 A = poolData[myPoolID(shID)].rbxFunded.mul(pShare(shID)).div(
            1e12
        );
        // Reward per second
        uint256 B = A.div(rPeriod);
        // Returns Actual reward
        uint256 C = Investors[shID].joinedTS.sub(
            poolData[myPoolID(shID)].startTS
        );
        uint256 G = C.mul(B);
        return G;
    }

    function unclaimedRBX(uint256 shID) private view returns (uint256) {
        if (Investors[shID].claimed == false) {
            return uRBXb(shID);
        }
        if (Investors[shID].claimed == true) {
            return 0;
        }
    }

    function unclaimedBNB(uint256 shID) private view returns (uint256) {
        if (Investors[shID].rClaimed == false) {
            return uBNBa(shID);
        }
        if (Investors[shID].rClaimed == true) {
            return 0;
        }
    }

    function iData(uint256 shID)
        public
        view
        returns (
            uint256 releaseTimeStamp2,
            uint256 payoutTimeStamp2,
            uint256 stakingWeight,
            uint256 shareOfThePool2,
            uint256 poolID2,
            uint256 claimedRBX,
            uint256 claimedBNB
        )
    {
        uint256 _earnedBNB = Investors[shID].accBNB;
        uint256 _earnedRBX = Investors[shID].accRBX.add(
            Investors[shID].accRBX2
        );
        uint256 _activePool = myPoolID(shID);
        return (
            Investors[shID].releaseTS,
            Investors[shID].rewardTS2,
            Investors[shID].sWeight,
            pShare(shID),
            _activePool,
            _earnedRBX,
            _earnedBNB
        );
    }

    function pData(uint256 pid)
        public
        view
        returns (
            uint256 timeCreated,
            uint256 poolExpiry,
            uint256 totalSh,
            uint256 apy,
            uint256 bnbFunded2,
            uint256 rbxFunded2,
            uint256 poolWeight
        )
    {
        return (
            poolData[pid].startTS,
            poolData[pid].endTS,
            poolData[pid].shIndex,
            yield,
            poolData[pid].bnbFunded,
            poolData[pid].rbxFunded,
            poolData[pid].poolWeight
        );
    }

    // Function for claiming only RBX rewards
    function claimA(uint256 shID) private {
        uint256 A = uRBXa(shID);
        if (timeLeft(shID) == true) {
            RBX.safeTransfer(msg.sender, A);
            Investors[shID].accRBX2 = Investors[shID].accRBX2.add(A);
        } else {
            RBX.safeTransfer(msg.sender, A.add(Investors[shID].sWeight));
            Investors[shID].accRBX2 = Investors[shID].accRBX2.add(A);
            Investors[shID].rClaimed = true;
            Investors[shID].claimed = true;
        }
    }

    // Function for claiming both assets
    function claimB(uint256 shID) private returns (bool) {
        uint256 A = uRBXb(shID);
        uint256 B = uRBXa(shID);
        uint256 C = uBNBa(shID);
        uint256 E = uBNBb(shID);
        uint256 D = uRBXe(shID);
        Investors[shID].accRBX = Investors[shID].accRBX.add(A);
        Investors[shID].accRBX2 = Investors[shID].accRBX2.add(B);
        Investors[shID].accBNB = Investors[shID].accBNB.add(C);
        if (uBNBb(shID) > 0) {
            wBNB.safeTransfer(jackpotPool, E);
            RBX.safeTransfer(jackpotPool, D);
        }
        if (timeLeft(shID) == false) {
            RBX.safeTransfer(msg.sender, A.add(B).add(Investors[shID].sWeight));
            wBNB.safeTransfer(msg.sender, C);
            Investors[shID].claimed = true;
            Investors[shID].rClaimed = true;
        } else {
            RBX.safeTransfer(msg.sender, A.add(B));
            wBNB.safeTransfer(msg.sender, C);
            subscribeToNewPool(shID);
        }
    }

    // Function for claiming both assets and initial investment
    function claimC(uint256 shID) private {
        uint256 A = uRBXb(shID);
        uint256 B = uRBXa(shID);
        uint256 C = uBNBa(shID);
        uint256 E = uBNBb(shID);
        uint256 D = uRBXe(shID);
        if (uBNBb(shID) > 0) {
            wBNB.safeTransfer(jackpotPool, E);
            RBX.safeTransfer(jackpotPool, D);
        }
        RBX.safeTransfer(msg.sender, A.add(B).add(Investors[shID].sWeight));
        wBNB.safeTransfer(msg.sender, C);
        Investors[shID].accRBX = Investors[shID].accRBX.add(A);
        Investors[shID].accRBX2 = Investors[shID].accRBX2.add(B);
        Investors[shID].accBNB = Investors[shID].accBNB.add(C);
        Investors[shID].claimed = true;
        Investors[shID].rClaimed = true;
    }

    // Function for claiming RBX if no BNB or RBX was funded
    function claimE(uint256 shID) private {
        uint256 A = uRBXa(shID);
        RBX.safeTransfer(msg.sender, A);
        Investors[shID].accRBX2 = Investors[shID].accRBX2.add(A);
        subscribeToNewPool(shID);
    }

    function subscribeToNewPool(uint256 shID) private {
        if (Investors[shID].releaseTS > poolData[_poolId].endTS) {
            poolData[_poolId].poolWeight = poolData[_poolId].poolWeight.add(
                Investors[shID].sWeight
            );
            Investors[shID].pid = _poolId;
            Investors[shID].joinedTS = poolData[_poolId].startTS;
            Investors[shID].rewardTS2 = poolData[_poolId].endTS;
            poolData[_poolId].shIndex = poolData[_poolId].shIndex.add(1);
        }
        if (Investors[shID].releaseTS < poolData[_poolId].endTS) {
            Investors[shID].rClaimed = true;
        }
    }

    function timeLeft(uint256 shID) private view returns (bool) {
        if (now >= Investors[shID].releaseTS) {
            return false;
        }
        if (now <= Investors[shID].releaseTS) {
            return true;
        }
    }

    function rewardClaimable(uint256 shID) private view returns (bool) {
        if (now <= Investors[shID].rewardTS2) {
            return false;
        }
        if (now >= Investors[shID].rewardTS2) {
            return true;
        }
    }

    function withdraw(uint256 shID) public returns (bool) {
        require(Investors[shID].claimed == false, "Reward already claimed");
        require(Investors[shID].user == msg.sender, "Not Investor");
        uint256 accRBX = uRBXa(shID);
        uint256 accBNB = uBNBa(shID);
        updatePool();
        if (accBNB > 0) {
            if (timeLeft(shID) == true) {
                if (rewardClaimable(shID) == false) {
                    claimA(shID);
                }
                if (rewardClaimable(shID) == true) {
                    if (Investors[shID].rClaimed == true) {
                        claimA(shID);
                    }
                    if (Investors[shID].rClaimed == false) {
                        claimB(shID);
                    }
                }
                emit claimed(msg.sender, accRBX, accBNB, shID, now);
            }
            if (timeLeft(shID) == false) {
                if (Investors[shID].rClaimed == true) {
                    claimA(shID);
                }
                if (Investors[shID].rClaimed == false) {
                    claimC(shID);
                }
            }
        }
        if (accBNB == 0) {
            if (timeLeft(shID) == true) {
                if (rewardClaimable(shID) == false) {
                    claimA(shID);
                }
                if (rewardClaimable(shID) == true) {
                    claimE(shID);
                }
            }
            if (timeLeft(shID) == false) {
                claimA(shID);
            }
            emit withdrew(
                msg.sender,
                accRBX,
                accBNB,
                shID,
                myPoolID(shID),
                now
            );
        }
        return true;
    }
}
