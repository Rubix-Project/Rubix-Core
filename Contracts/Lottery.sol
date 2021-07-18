//SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "./Ownable.sol";
import "./IBEP20.sol";
import "./SafeMath.sol";
import "./SafeBEP20.sol";
import "./ChainLinkVRF.sol"; // Chainlink random number generator interface
import "./ISTAKE.sol";

contract Lottery is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    
    event BuyTicketsWithDicscount(address indexed player, uint quantity, uint ticketID, uint roundID);
    event BuyTicketsWithoutDicscount(address indexed player, uint quantity, uint ticketID, uint roundID);
    event Claim(address indexed);
    event RandomNumberGenerator();
    event DrawLuckyNumbers(uint roundID);

    receive() external payable {
        require(msg.sender == wBNBaddress, "wBNB ONLY!");
    }

    //Constants
    uint256 internal constant DEVS_SHARE = 10;
    uint256 internal constant COMMUNITY_SHARE = 10;
    uint256 constant SECONDS_IN_DAY = 86400;

    //Interfaces
    IVRF internal VRF; // Random Number Generator
    IBEP20 internal RBX; // Rubix Token
    IBEP20 internal wBNB; // wBNB Interace
    ISTAKE internal STAKING;
    address payable public immutable wBNBaddress;

    // Dev and staking addresses
    address private STAKINGADDRESS;
    address private DEVADDRESS;

    mapping(address => Balances) private balanceToClaim;

    struct Balances {
        uint256 RBX;
        uint256 wBNB;
    }

    /* Stores data about every ticket bought during draws. */
    mapping(uint256 => TICKETDATA) private _TICKETDATA;

    struct TICKETDATA {
        address payable PLAYER_ADDRESS;
        uint256 ROUND_JOINED;
        uint256 TICKETS_BOUGHT;
        uint256[4] LUCKY_NUMBERS;
        uint256 One;
        uint256 Two;
        uint256 Three;
        uint256 Jackpot;
        uint8 MATCHED;
    }

    /* Stores data about winners and lottery rounds */
    mapping(uint256 => ROUND) private ROUNDS;

    struct ROUND {
        uint256 TICKETS_SOLD;
        uint256[4] WINNING_NUMBERS;
        uint8 WINNERS_PICKED; // 0 - Winners not Picked, 1 Winners Picked
        uint256 ROUND_START_TIMESTAMP;
        uint256 ROUND_END_TIMESTAMP;
        uint256 FIRST_POT_RBX;
        uint256 SECOND_POT_RBX;
        uint256 THIRD_POT_RBX;
        uint256 FIRST_POT_wBNB;
        uint256 SECOND_POT_wBNB;
        uint256 THIRD_POT_wBNB;
    }

    mapping(uint256 => POOL) private POOLS;

    struct POOL {
        uint256 REGULAR_PRIZE_RBX;
        uint256 REGULAR_PRIZE_wBNB;
        uint16 MATCHED_1_NUMBER;
        uint16 MATCHED_2_NUMBERS;
        uint16 MATCHED_3_NUMBERS;
        uint16 MATCHED_4_NUMBERS;
    }

    // Stores data about every player
    address[] private PLAYERS;

    //Lottery related stuff
    uint256 constant GAME_LENGTH = 100;
    uint256 internal RANDOM_NUMBER;
    uint256 internal TICKET_FEE_wBNB = 0.015 * 10**18; // 0.015 BNB
    uint256 internal TICKET_FEE_RBX = 15 * 10**18; // 15 RBX

    uint256 private JACKPOT_PRIZE_wBNB;
    uint256 private JACKPOT_PRIZE_RBX;
    uint256 internal ACTIVE_POOL;
    uint256 private TICKETS_PURCHASED = 0;
    uint256 private TOTAL_TICKETS_SOLD;

    constructor(
        address payable _wBNBAddress,
        IVRF _VRF,
        IBEP20 _RBX,
        IBEP20 _wBNB,
        address _DEV,
        address _STAKING,
        ISTAKE _STAKING2
    ) public {
        VRF = _VRF;
        wBNBaddress = _wBNBAddress;
        RBX = _RBX;
        wBNB = _wBNB;
        DEVADDRESS = _DEV;
        STAKINGADDRESS = _STAKING;
        STAKING = _STAKING2;
    }

    function isPlayer(uint256 id, address _address) public view returns (bool) {
        if (PLAYERS[id] == _address) {
            return true;
        } else {
            return false;
        }
    }

    /* @dev Lottery buy functions */
    function buyWithoutDiscount(uint256 QTY)
        external
        payable
        returns (uint8 success)
    {
        require(QTY <= 50, "RBX LOTTERY: MAX 50 IS ALLOWED");
        require(QTY > 0, "RBX LOTTERY: INCORRECT VALUE");

        updatePool();
        uint256 FINAL_DUE = TICKET_FEE_wBNB.mul(QTY);

        if (msg.value > 0) {
            require(msg.value >= FINAL_DUE, "RBX LOTTERY: Wrong value");
            wrapBNB();
        }

        if (msg.value == 0) {
            wBNB.safeTransferFrom(msg.sender, address(this), FINAL_DUE);
        }

        sendShares(QTY, 1);

        PLAYERS.push(msg.sender);

        uint256[2] memory _JACKPOT_TREASURY = calcJackpot(QTY, 1);
        JACKPOT_PRIZE_wBNB = JACKPOT_PRIZE_wBNB.add(_JACKPOT_TREASURY[0]);

        uint256[2] memory _REGULAR_POT = calcRegularPot(QTY, 1);
        POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_wBNB
        .add(_REGULAR_POT[0]);
        ROUNDS[ACTIVE_POOL].TICKETS_SOLD = ROUNDS[ACTIVE_POOL].TICKETS_SOLD.add(
            QTY
        );

        if (QTY == 1) {
            uint[] memory R = expand(now, 4);
            _TICKETDATA[TICKETS_PURCHASED] = TICKETDATA(
                _msgSender(),
                ACTIVE_POOL,
                QTY,
                [
                    (RandomNumber(R[0]) % 25),
                    (RandomNumber(R[1]) % 25),
                    (RandomNumber(R[2]) % 25),
                    (RandomNumber(R[3]) % 10)
                ],
                0,
                0,
                0,
                0,
                0
            );
        } else {
            for (
                uint256 i = TICKETS_PURCHASED;
                i <= TICKETS_PURCHASED.add(QTY - 1);
                i++
            ) {
                uint[] memory R = expand(i, 4);
                _TICKETDATA[i] = TICKETDATA(
                    _msgSender(),
                    ACTIVE_POOL,
                    QTY,
                    [
                        (RandomNumber(R[0]) % 25),
                        (RandomNumber(R[1]) % 25),
                        (RandomNumber(R[2]) % 25),
                        (RandomNumber(R[3]) % 10)
                    ],
                    0,
                    0,
                    0,
                    0,
                    0
                );
            }
        }
        TICKETS_PURCHASED = TICKETS_PURCHASED.add(QTY);
        TOTAL_TICKETS_SOLD = TOTAL_TICKETS_SOLD.add(QTY);
        emit BuyTicketsWithoutDicscount(msg.sender, QTY, TICKETS_PURCHASED.sub(1), ACTIVE_POOL);
        return 1;
    }

    function buyWithDiscount(uint256 QTY)
        external
        payable
        returns (uint8 success)
    {
        require(QTY <= 50, "RBX LOTTERY: MAX 50 IS ALLOWED");
        require(QTY > 0, "RBX LOTTERY: INCORRECT VALUE");

        updatePool();

        uint256 FINAL_DUE_RBX = TICKET_FEE_RBX.mul(QTY);

        RBX.safeTransferFrom(msg.sender, address(this), FINAL_DUE_RBX);

        sendShares(QTY, 0);
        PLAYERS.push(msg.sender);

        uint256[2] memory _JACKPOT_TREASURY = calcJackpot(QTY, 0);
        JACKPOT_PRIZE_RBX = JACKPOT_PRIZE_RBX.add(_JACKPOT_TREASURY[1]);

        uint256[2] memory _REGULAR_POT = calcRegularPot(QTY, 0);
        POOLS[ACTIVE_POOL].REGULAR_PRIZE_RBX = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_RBX
        .add(_REGULAR_POT[1]);

        ROUNDS[ACTIVE_POOL].TICKETS_SOLD = ROUNDS[ACTIVE_POOL].TICKETS_SOLD.add(
            QTY
        );

        if (QTY == 1) {
            uint256[] memory R = expand(now, 4);
            _TICKETDATA[TICKETS_PURCHASED] = TICKETDATA(
                _msgSender(),
                ACTIVE_POOL,
                QTY,
                [
                    (RandomNumber(R[0]) % 25),
                    (RandomNumber(R[1]) % 25),
                    (RandomNumber(R[2]) % 25),
                    (RandomNumber(R[3]) % 10)
                ],
                0,
                0,
                0,
                0,
                0
            );
        } else {
            for (
                uint256 i = TICKETS_PURCHASED;
                i <= TICKETS_PURCHASED.add(QTY - 1);
                i++
            ) {
                uint[] memory R = expand(i, 4); // Random number generator
                _TICKETDATA[i] = TICKETDATA(
                    _msgSender(),
                    ACTIVE_POOL,
                    QTY,
                    [
                        (RandomNumber(R[0]) % 25),
                        (RandomNumber(R[1]) % 25),
                        (RandomNumber(R[2]) % 25),
                        (RandomNumber(R[3]) % 10)
                    ],
                    0,
                    0,
                    0,
                    0,
                    0
                );
            }
        }
        TICKETS_PURCHASED = TICKETS_PURCHASED.add(QTY);
        TOTAL_TICKETS_SOLD = TOTAL_TICKETS_SOLD.add(QTY);
        emit BuyTicketsWithDicscount(msg.sender, QTY, TICKETS_PURCHASED.sub(1), ACTIVE_POOL);
        return 1;
    }

    /* Claim functions */
    function claim() public returns (bool success) {
        require(
            balanceToClaim[msg.sender].RBX > 0 ||
                balanceToClaim[msg.sender].wBNB > 0,
            "RBX Lottery: No reward to claim"
        );
        uint256 RBXToClaim = balanceToClaim[msg.sender].RBX;
        uint256 wBNBToClaim = balanceToClaim[msg.sender].wBNB;

        RBX.safeTransfer(msg.sender, RBXToClaim);
        wBNB.safeTransfer(msg.sender, wBNBToClaim);

        balanceToClaim[msg.sender].RBX = 0;
        balanceToClaim[msg.sender].wBNB = 0;
        emit Claim (msg.sender);
        return true;
    }

    /* @dev Lottery related functions */

    function updatePool() private {
        if (ROUNDS[ACTIVE_POOL].ROUND_END_TIMESTAMP == 0) {
            ROUNDS[ACTIVE_POOL].ROUND_START_TIMESTAMP = now;
            ROUNDS[ACTIVE_POOL].ROUND_END_TIMESTAMP = now.add(GAME_LENGTH);
        }
        if (ROUNDS[ACTIVE_POOL].ROUND_END_TIMESTAMP <= now) {
            if (ROUNDS[ACTIVE_POOL].TICKETS_SOLD <= 109) {
                ROUNDS[ACTIVE_POOL].ROUND_END_TIMESTAMP = now.add(GAME_LENGTH);
            }
            if (ROUNDS[ACTIVE_POOL].TICKETS_SOLD > 49) {
                require(
                    ROUNDS[ACTIVE_POOL].WINNERS_PICKED == 1,
                    "RBX: Winner needs to picked first!"
                );
                ACTIVE_POOL++;
                TOTAL_TICKETS_SOLD = TOTAL_TICKETS_SOLD.add(TICKETS_PURCHASED);
                TICKETS_PURCHASED = 0;
                ROUNDS[ACTIVE_POOL].ROUND_START_TIMESTAMP = now;
                ROUNDS[ACTIVE_POOL].ROUND_END_TIMESTAMP = now.add(GAME_LENGTH);
                delete PLAYERS;
            }
        }
    }

    function updatePots() internal {
        ROUNDS[ACTIVE_POOL].FIRST_POT_RBX = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_RBX
        .mul(20)
        .div(100);
        ROUNDS[ACTIVE_POOL].SECOND_POT_RBX = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_RBX
        .mul(30)
        .div(100);
        ROUNDS[ACTIVE_POOL].THIRD_POT_RBX = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_RBX
        .mul(50)
        .div(100);

        ROUNDS[ACTIVE_POOL].FIRST_POT_wBNB = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_wBNB
        .mul(20)
        .div(100);
        ROUNDS[ACTIVE_POOL].SECOND_POT_wBNB = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_wBNB
        .mul(30)
        .div(100);
        ROUNDS[ACTIVE_POOL].THIRD_POT_wBNB = POOLS[ACTIVE_POOL]
        .REGULAR_PRIZE_wBNB
        .mul(50)
        .div(100);
    }

    function drawLuckyNumbers() public returns (bool) {
        require(
            now >= ROUNDS[ACTIVE_POOL].ROUND_END_TIMESTAMP,
            "RBX: Lottery in progress!"
        );
        require(
            VRF.returnRandomness() > 0,
            "RBX:Random numbers not generated yet"
        );
        require(
            VRF.returnRandomness() != RANDOM_NUMBER,
            "RBX:Random numbers not generated yet"
        );
        uint256[] memory _RandomNumber = expand(VRF.returnRandomness(), 4);
        ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[0] = 4;
        ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[1] = (_RandomNumber[1] % 5);
        ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[2] = (_RandomNumber[2] % 5);
        ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[3] = (_RandomNumber[3] % 10);
        updatePots();
        countWinners();
        updateWinnerBalances();
        moveUnspent();
        updatePool();
        RANDOM_NUMBER = VRF.returnRandomness();
        emit DrawLuckyNumbers(ACTIVE_POOL);
        return true;
    }

    //Wrap BNB
    function wrapBNB() public payable {
        require(msg.value > 0);
        IBEP20(wBNBaddress).deposit{value: msg.value}();
        IBEP20(wBNBaddress).transfer(address(this), msg.value);
    }

    function countWinners() internal {
        for (uint256 i = 0; i < TICKETS_PURCHASED.sub(1); i++) {
            if (_TICKETDATA[i].MATCHED == 0) {
                if (
                    _TICKETDATA[i].LUCKY_NUMBERS[0] ==
                    ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[0] &&
                    _TICKETDATA[i].LUCKY_NUMBERS[1] ==
                    ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[1] &&
                    _TICKETDATA[i].LUCKY_NUMBERS[2] ==
                    ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[2] &&
                    _TICKETDATA[i].LUCKY_NUMBERS[3] ==
                    ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[3] &&
                    _TICKETDATA[i].MATCHED != 1
                ) {
                    _TICKETDATA[i].MATCHED = 1;
                    _TICKETDATA[i].Jackpot = _TICKETDATA[i].Jackpot.add(1);
                }
                POOLS[ACTIVE_POOL].MATCHED_4_NUMBERS + 1;
            }
            if (
                _TICKETDATA[i].LUCKY_NUMBERS[0] ==
                ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[0] &&
                _TICKETDATA[i].LUCKY_NUMBERS[1] ==
                ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[1] &&
                _TICKETDATA[i].LUCKY_NUMBERS[2] ==
                ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[2] &&
                _TICKETDATA[i].MATCHED != 1
            ) {
                _TICKETDATA[i].Three = _TICKETDATA[i].Three.add(1);
                POOLS[ACTIVE_POOL].MATCHED_3_NUMBERS =
                    POOLS[ACTIVE_POOL].MATCHED_3_NUMBERS +
                    1;
                _TICKETDATA[i].MATCHED = 1;
            }
            if (
                _TICKETDATA[i].LUCKY_NUMBERS[0] ==
                ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[0] &&
                _TICKETDATA[i].LUCKY_NUMBERS[1] ==
                ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[1] &&
                _TICKETDATA[i].MATCHED != 1
            ) {
                _TICKETDATA[i].MATCHED = 1;
                _TICKETDATA[i].Two = _TICKETDATA[i].Two.add(1);

                POOLS[ACTIVE_POOL].MATCHED_2_NUMBERS =
                    POOLS[ACTIVE_POOL].MATCHED_2_NUMBERS +
                    1;
            }
            if (
                _TICKETDATA[i].LUCKY_NUMBERS[0] ==
                ROUNDS[ACTIVE_POOL].WINNING_NUMBERS[0] &&
                _TICKETDATA[i].MATCHED != 1
            ) {
                _TICKETDATA[i].MATCHED = 1;
                _TICKETDATA[i].One = _TICKETDATA[i].One.add(1);
                POOLS[ACTIVE_POOL].MATCHED_1_NUMBER =
                    POOLS[ACTIVE_POOL].MATCHED_1_NUMBER +
                    1;
            }
        }
    }

    function moveUnspent() internal {
        if (POOLS[ACTIVE_POOL].MATCHED_1_NUMBER == 0) {
            ROUNDS[ACTIVE_POOL.add(1)].FIRST_POT_RBX = ROUNDS[ACTIVE_POOL].FIRST_POT_RBX;
            
            ROUNDS[ACTIVE_POOL.add(1)].FIRST_POT_wBNB = ROUNDS[ACTIVE_POOL].FIRST_POT_wBNB;

            ROUNDS[ACTIVE_POOL].FIRST_POT_RBX = 0;
            ROUNDS[ACTIVE_POOL].FIRST_POT_wBNB = 0;
        }
        if (POOLS[ACTIVE_POOL].MATCHED_2_NUMBERS == 0) {
            ROUNDS[ACTIVE_POOL.add(1)].SECOND_POT_RBX = ROUNDS[ACTIVE_POOL].SECOND_POT_RBX;

            ROUNDS[ACTIVE_POOL.add(1)].SECOND_POT_wBNB = ROUNDS[ACTIVE_POOL].SECOND_POT_wBNB;

            ROUNDS[ACTIVE_POOL].SECOND_POT_RBX = 0;
            ROUNDS[ACTIVE_POOL].SECOND_POT_wBNB = 0;
        }

        if (POOLS[ACTIVE_POOL].MATCHED_3_NUMBERS == 0) {
            ROUNDS[ACTIVE_POOL.add(1)].THIRD_POT_RBX = ROUNDS[ACTIVE_POOL].THIRD_POT_RBX;
            
            ROUNDS[ACTIVE_POOL.add(1)].THIRD_POT_wBNB = ROUNDS[ACTIVE_POOL].THIRD_POT_wBNB;

            ROUNDS[ACTIVE_POOL].THIRD_POT_RBX = 0;
            ROUNDS[ACTIVE_POOL].THIRD_POT_wBNB = 0;
        }
        ROUNDS[ACTIVE_POOL].WINNERS_PICKED = 1;
    }

    function updateWinnerBalances() internal {
        for (uint256 i = 0; i < TICKETS_PURCHASED.sub(1); i++) {
            if (_TICKETDATA[i].Jackpot > 0) {
                uint256 JackPotPerTicketwBNB = JACKPOT_PRIZE_wBNB.div(
                    POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_4_NUMBERS
                );
                uint256 JackPotPerTicketRBX = JACKPOT_PRIZE_RBX.div(
                    POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_4_NUMBERS
                );
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .wBNB = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].wBNB.add(
                    JackPotPerTicketwBNB
                );
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .RBX = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].RBX.add(
                    JackPotPerTicketRBX
                );
            }

            if (_TICKETDATA[i].Three > 0) {
                uint256 PrizePerTicketwBNB = ROUNDS[_TICKETDATA[i].ROUND_JOINED]
                .THIRD_POT_wBNB
                .div(POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_3_NUMBERS);
                uint256 PrizePerTicketRBX = ROUNDS[_TICKETDATA[i].ROUND_JOINED]
                .THIRD_POT_RBX
                .div(POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_3_NUMBERS);
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .wBNB = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].wBNB.add(
                    PrizePerTicketwBNB
                );
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .RBX = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].RBX.add(
                    PrizePerTicketRBX
                );
            }

            if (_TICKETDATA[i].Two > 0) {
                uint256 PrizePerTicketwBNB = ROUNDS[_TICKETDATA[i].ROUND_JOINED]
                .SECOND_POT_wBNB
                .div(POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_2_NUMBERS);
                uint256 PrizePerTicketRBX = ROUNDS[_TICKETDATA[i].ROUND_JOINED]
                .SECOND_POT_RBX
                .div(POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_2_NUMBERS);
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .wBNB = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].wBNB.add(
                    PrizePerTicketwBNB
                );
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .RBX = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].RBX.add(
                    PrizePerTicketRBX
                );
            }

            if (_TICKETDATA[i].One > 0) {
                uint256 PrizePerTicketwBNB = ROUNDS[_TICKETDATA[i].ROUND_JOINED]
                .FIRST_POT_wBNB
                .div(POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_1_NUMBER);
                uint256 PrizePerTicketRBX = ROUNDS[_TICKETDATA[i].ROUND_JOINED]
                .FIRST_POT_RBX
                .div(POOLS[_TICKETDATA[i].ROUND_JOINED].MATCHED_1_NUMBER);
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .wBNB = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].wBNB.add(
                    PrizePerTicketwBNB
                );
                balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS]
                .RBX = balanceToClaim[_TICKETDATA[i].PLAYER_ADDRESS].RBX.add(
                    PrizePerTicketRBX
                );
            }
        }
    }

    function sendShares(uint256 QTY, uint16 condition) internal {
        uint256 FEE_wBNB = QTY.mul(TICKET_FEE_wBNB);
        uint256 FEE_RBX = QTY.mul(TICKET_FEE_RBX);

        uint256 Devs_RBX_Share = FEE_RBX.mul(DEVS_SHARE) / 100;
        uint256 Community_RBX_Share = FEE_RBX.mul(COMMUNITY_SHARE) / 100;

        uint256 Devs_wBNB_Share = FEE_wBNB.mul(DEVS_SHARE) / 100;

        uint256 Community_wBNB_Share = FEE_wBNB.mul(COMMUNITY_SHARE) / 100;

        if (condition == 1) {
            wBNB.safeTransfer(STAKINGADDRESS, Community_wBNB_Share);
            wBNB.safeTransfer(DEVADDRESS, Devs_wBNB_Share);
            STAKING.topUp(Community_wBNB_Share, 0);
        }

        if (condition == 0) {
            RBX.safeTransfer(STAKINGADDRESS, Community_RBX_Share);
            RBX.safeTransfer(DEVADDRESS, Devs_RBX_Share);
            STAKING.topUp(0, Community_RBX_Share);
        }
    }
    
    function addFundsToPool(uint256 _RBX, uint256 _BNB) public payable {
        if(_RBX > 0 && _BNB > 0) {
            if(msg.value != 0 ) {
                wrapBNB();
                POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB = POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB.add(_BNB.div(2));
                JACKPOT_PRIZE_wBNB = JACKPOT_PRIZE_wBNB.add(_BNB.div(2));
            } if(msg.value == 0) {
                wBNB.safeTransferFrom(msg.sender, address(this), _BNB);
                POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB = POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB.add(_BNB.div(2));
                JACKPOT_PRIZE_wBNB = JACKPOT_PRIZE_wBNB.add(_BNB.div(2));
            }
            RBX.safeTransferFrom(msg.sender, address(this), _RBX);
            POOLS[ACTIVE_POOL].REGULAR_PRIZE_RBX = POOLS[ACTIVE_POOL].REGULAR_PRIZE_RBX.add(_RBX.div(2));
            JACKPOT_PRIZE_RBX = JACKPOT_PRIZE_RBX.add(_RBX.div(2));
        } if(_RBX > 0 && _BNB == 0) {
            RBX.safeTransferFrom(msg.sender, address(this), _RBX);
            POOLS[ACTIVE_POOL].REGULAR_PRIZE_RBX = POOLS[ACTIVE_POOL].REGULAR_PRIZE_RBX.add(_RBX.div(2));
            JACKPOT_PRIZE_RBX = JACKPOT_PRIZE_RBX.add(_RBX.div(2));
        } else {
            if(msg.value != 0 ) {
                wrapBNB();
                POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB = POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB.add(_BNB.div(2));
                JACKPOT_PRIZE_wBNB = JACKPOT_PRIZE_wBNB.add(_BNB.div(2));
            } if(msg.value == 0) {
                wBNB.safeTransferFrom(msg.sender, address(this), _BNB);
                POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB = POOLS[ACTIVE_POOL].REGULAR_PRIZE_wBNB.add(_BNB.div(2));
                JACKPOT_PRIZE_wBNB = JACKPOT_PRIZE_wBNB.add(_BNB.div(2));
            }
            
        }
        
    }

    /* Random Number Generator */

    function getNewRandomNumber() public {
        VRF.getRandomNumber();
    }

    function RandomNumber(uint256 ONE) internal view returns (uint256) {
        uint256 RANDOM = uint256(
            keccak256(
                abi.encodePacked(
                    block.number,
                    block.timestamp,
                    TICKETS_PURCHASED,
                    ONE
                )
            )
        );
        return RANDOM;
    }

    function expand(uint256 randomValue, uint256 n)
        internal
        pure
        returns (uint256[] memory expandedValues)
    {
        expandedValues = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            expandedValues[i] = uint256(keccak256(abi.encode(randomValue, i)));
        }
        return expandedValues;
    }

    /* VIEW FUNCTIONS */

    function getWinningNumbers(uint256 ROUND_NUMBER)
        public
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        uint256 a = ROUNDS[ROUND_NUMBER].WINNING_NUMBERS[0];
        uint256 b = ROUNDS[ROUND_NUMBER].WINNING_NUMBERS[1];
        uint256 c = ROUNDS[ROUND_NUMBER].WINNING_NUMBERS[2];
        uint256 d = ROUNDS[ROUND_NUMBER].WINNING_NUMBERS[3];
        return (a, b, c, d);
    }

    function getTicketData(uint256 ticketID)
        public
        view
        returns (
            address player,
            uint256 ticketsPurchased,
            uint256[4] memory LuckyNumbers,
            uint256 Round
        )
    {
        return (
            _TICKETDATA[ticketID].PLAYER_ADDRESS,
            _TICKETDATA[ticketID].TICKETS_BOUGHT,
            _TICKETDATA[ticketID].LUCKY_NUMBERS,
            _TICKETDATA[ticketID].ROUND_JOINED

        );
    }
    
    
    function isWinner(uint256 ticketID) public view returns(
        uint256 OneNumberPlayed,
        uint256 TwoNumberPlayed,
        uint256 ThreeNumberPlayed,
        uint256 FourNumberPlayed) {
        
        return(
            _TICKETDATA[ticketID].One,
            _TICKETDATA[ticketID].Two,
            _TICKETDATA[ticketID].Three,
            _TICKETDATA[ticketID].Jackpot);
    }
    
    function _balanceOf(address _address) public view returns(uint _RBX, uint BNB) {
        return(balanceToClaim[_address].RBX, balanceToClaim[_address].wBNB);
    }
    
    function getlotteryInfo(uint256 ROUND_ID) public view returns(uint _TICKETS_SOLD, uint JackPotRBX, uint JackpotBNB, uint regularPotRBX, uint regularBNB, uint totalTicketSold) {
        return(ROUNDS[ROUND_ID].TICKETS_SOLD, JACKPOT_PRIZE_RBX, JACKPOT_PRIZE_wBNB, POOLS[ROUND_ID].REGULAR_PRIZE_RBX, POOLS[ROUND_ID].REGULAR_PRIZE_wBNB, TOTAL_TICKETS_SOLD);
    }
    
    

    /* PRIVATE VIEW FUNCTIONS */
    function calcJackpot(uint256 TICKET_QTY, uint8 CONDITION)
        internal
        view
        returns (uint256[2] memory)
    {
        uint256 TOTAL_FEE = TICKET_FEE_wBNB.mul(TICKET_QTY);
        uint256 TOTAL_FEE_RBX = TICKET_FEE_RBX.mul(TICKET_QTY);

        uint256 TOTAL_FEE_AFTER_DIST_wBNB = TOTAL_FEE.mul(80).div(100);
        uint256 TOTAL_FEE_AFTER_DIST_RBX = TOTAL_FEE_RBX.mul(80).div(100);

        uint256 JACKPOT_TREASURY_wBNB = TOTAL_FEE_AFTER_DIST_wBNB.mul(45).div(
            100
        );
        uint256 JACKPOT_TREASURY_RBX = TOTAL_FEE_AFTER_DIST_RBX.mul(45).div(
            100
        );

        if (CONDITION == 0) {
            return ([0, JACKPOT_TREASURY_RBX]);
        } else {
            return ([JACKPOT_TREASURY_wBNB, 0]);
        }
    }

    function calcRegularPot(uint256 TICKET_QTY, uint8 CONDITION)
        internal
        view
        returns (uint256[2] memory)
    {
        uint256 TOTAL_FEE_wBNB = TICKET_FEE_wBNB.mul(TICKET_QTY);
        uint256 TOTAL_FEE_RBX = TICKET_FEE_RBX.mul(TICKET_QTY);

        uint256 TOTAL_FEE_AFTER_DIST_wBNB = TOTAL_FEE_wBNB.mul(80).div(100);
        uint256 TOTAL_FEE_AFTER_DIST_RBX = TOTAL_FEE_RBX.mul(80).div(100);

        uint256 _REGULAR_PRIZE_wBNB = TOTAL_FEE_AFTER_DIST_wBNB.mul(55).div(
            100
        );
        uint256 _REGULAR_PRIZE_RBX = TOTAL_FEE_AFTER_DIST_RBX.mul(55).div(100);

        if (CONDITION == 0) {
            return ([0, _REGULAR_PRIZE_RBX]);
        } else {
            return ([_REGULAR_PRIZE_wBNB, 0]);
        }
    }
}
