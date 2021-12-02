// contracts/DanceOff.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IHgh.sol";
import "./interface/IMaticMike.sol";

contract DanceOff is VRFConsumerBase, Ownable{
    using Counters for Counters.Counter;
    Counters.Counter private _rumbleId;
    Counters.Counter private _pvpId;
    Counters.Counter private _challengeId;

    struct RollInfo{
        uint256 tokenId;
        address holder;
        uint256 roll;
    }

    struct BattleType{
        uint8 battleType;
        uint256 battleId;
        uint256 tokenId;
        uint8 juicedUp;
        uint256 wager;
    }

    struct Winner{
        uint256 tokenId;
        uint8 placement;
        uint256 rumbleId;
        uint256 payout;
        address holder;
    }

    struct Leaderboards{
        uint256[] firstP;
        uint256[] secondP;
        uint256[] thirdP;
    }

    uint256[] firstPlacements;
    uint256[] secondPlacements;
    uint256[] thirdPlacements;
    uint256[] noPlacements;

    // Track participants
    mapping(uint256 => RollInfo[]) rumbleIdToRolls;
    mapping(bytes32 => BattleType) responseIdToBattle;
    
    mapping(uint256 => bool) battleIsComplete;
    mapping(uint256 => Winner[]) battleIdToWinners;
    mapping(uint256 => uint256) royaleTimeTrigger;
    mapping(uint256 => uint8) royaleParticipants;
    mapping(uint256 => uint8) royaleProcessedLink;
    mapping(uint256 => uint256) royalePot;

    mapping(uint256 => mapping(uint256 => bool)) tokenToRumble;
    
    // analytical stuff
    mapping(uint256 => uint256[]) tokenToRumblesEntered;
    mapping(uint256 => Winner[]) tokenToWinner;
    mapping(uint256 => uint256[]) rumbleIdParticipants;

    mapping(address => Winner[]) addressToWinner;
    mapping(address => uint256[]) addressToRumblesEntered;

    // 
    uint256 wagerMulti = 1000000000000000000;
    uint256 currentPrice = 1000000000000000000;
    uint8 rumbleSize = 50;
    uint8 minimumSize = 20;
    uint256 maxTime = 1800; // 30 minute trigger
    uint8 maxJuice = 5;

    address hghAddress;
    address mmAddress;

    bytes32 private keyHash;
    uint256 private fee;

    Leaderboards leaders;

    bool public active = false;

    // Mainnet
    // LINK Token	0xb0897686c545045aFc77CF20eC7A532E3120E0F1
    // VRF Coordinator	0x3d2341ADb2D31f1c5530cDC622016af293177AE0
    // Key Hash	0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da
    // Fee	0.0001 LINK

    // Mumbai
    // LINK Token	0x326C977E6efc84E512bB9C30f76E30c160eD06FB
    // VRF Coordinator	0x8C7382F9D8f56b33781fE506E897a4F1e2d17255
    // Key Hash	0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4
    // Fee	0.0001 LINK

    constructor() 
        VRFConsumerBase(0x3d2341ADb2D31f1c5530cDC622016af293177AE0, 0xb0897686c545045aFc77CF20eC7A532E3120E0F1)
    {
        // Chainlink Info
        keyHash = 0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da;
        fee = 0.0001 * 10 ** 18; // 0.0001 LINK
        royaleTimeTrigger[_rumbleId.current()] = block.timestamp;
    }

    // owner functions set everything
    function setTimeTriggerNow() public onlyOwner{
        royaleTimeTrigger[_rumbleId.current()] = block.timestamp;
    }

    function setActive(bool _active) public onlyOwner{
        active = _active;
    }

    function setAddress(address _hghAddress, address _mmAddress) public onlyOwner{
        hghAddress = _hghAddress;
        mmAddress = _mmAddress;
    }

    function setPrice(uint256 _price) public onlyOwner{
        currentPrice = _price;
    }

    function setRumbleSize(uint8 _size) public onlyOwner{
        rumbleSize = _size;
    }

    function setMinSize(uint8 _size) public onlyOwner{
        minimumSize = _size;
    }

    function setMaxTime(uint256 _time) public onlyOwner{
        maxTime = _time;
    }

    function withdrawHghIfStuck() public onlyOwner{
        uint256 balance = IHgh(hghAddress).balanceOf(address(this));
        IHgh(hghAddress).transfer(msg.sender, balance);
    }

    function forceStart(uint256 rumbleId) public onlyOwner{
        beginDance(rumbleId);
    }

    function setLinkFee(uint256 _fee) public onlyOwner{
        fee = _fee;
    }

    function setMaxJuice(uint8 _maxJuice)public onlyOwner{
        maxJuice = _maxJuice;
    }

    // end owner functions

    // // analytical stuff
    // mapping(uint256 => uint256[]) tokenToRumblesEntered;
    function getMaxJuice() public view returns (uint8){
        return maxJuice;
    }

    function getCurrentRumble() public view returns (uint256){
        return _rumbleId.current();
    }

    function getCurrentPot() public view returns (uint256){
        return royalePot[_rumbleId.current()];
    }

    function getCurrentEntries() public view returns (uint8){
        return royaleParticipants[_rumbleId.current()];
    }
    
    function getTimeTrigger() public view returns (uint256){
        return royaleTimeTrigger[_rumbleId.current()];
    }

    function isComplete(uint256 rumbleId) public view returns (bool){
        return battleIsComplete[rumbleId];
    }

    function getRumblesEntered(uint256 _tokenId) public view returns (uint256[] memory){
        return tokenToRumblesEntered[_tokenId];
    }

    function getPlacementsByToken(uint256 _tokenId) public view returns (Winner[] memory){
        return tokenToWinner[_tokenId];
    }

    function getPlacementsByAddress(address _address) public view returns (Winner[] memory){
        return addressToWinner[_address];
    }

    function getRumblesEnteredByAddress(address _address) public view returns (uint256[] memory){
        return addressToRumblesEntered[_address];
    }

    function getPlacementsByRumble(uint256 rumbleId) public view returns (Winner[] memory){
        return battleIdToWinners[rumbleId];
    }

    function getEntriesByRumble(uint256 rumbleId) public view returns (uint256[] memory){
        return rumbleIdParticipants[rumbleId];
    }

    function getLeaderboards() public view returns (Leaderboards memory){
        return leaders;
    }

    function getFirstPlace() public view returns (uint256[] memory){
        return firstPlacements;
    }

    function getSecondPlace() public view returns (uint256[] memory){
        return secondPlacements;
    }

    function getThirdPlace() public view returns (uint256[] memory){
        return thirdPlacements;
    }

    // enter battle royale
    function enterRoyale(uint256 _tokenId, uint8 _hghJuice) public returns (uint256){
        require(active, "Dance Royale not currently active");
        require((_hghJuice * wagerMulti) % wagerMulti == 0, "HGH Amount cannot be a decimal");
        require(_hghJuice <= maxJuice, "Over the maximum juice amount");
        require(IHgh(hghAddress).balanceOf(msg.sender) >= (_hghJuice * wagerMulti) + currentPrice, "Not enough HGH in wallet balance");
        
        // check in gym as well 
        require(IMaticMike(mmAddress).ownerOf(_tokenId) == msg.sender || IHgh(hghAddress).getStaker(_tokenId) == msg.sender, "Not the owner of token");
        require(royaleParticipants[_rumbleId.current()] < rumbleSize && !battleIsComplete[_rumbleId.current()], "Royale trigger currently in progress. Try again in a minute");
        
        // require that they are not already entered in the competition...
        require(!tokenToRumble[_tokenId][_rumbleId.current()], "Already entered in competition");

        // if new rumble populate analytics from previous rumble
        if(_rumbleId.current() != 0 && royaleParticipants[_rumbleId.current()] == 0){
            populateWinners(_rumbleId.current() - 1);
        }

        // burn the juiced up amount
        IHgh(hghAddress).burnFrom(msg.sender, _hghJuice * wagerMulti);

        // transfer 1 HGH to contract
        IHgh(hghAddress).transferFrom(msg.sender, address(this), currentPrice);

        // begin royale entry
        royaleParticipants[_rumbleId.current()]++;
        royalePot[_rumbleId.current()] = royalePot[_rumbleId.current()] + wagerMulti;
        tokenToRumble[_tokenId][_rumbleId.current()] = true;
        
        bytes32 requestId = requestRandomness(keyHash, fee);

        responseIdToBattle[requestId] = BattleType(
            1,
            _rumbleId.current(),
            _tokenId,
            _hghJuice,
            wagerMulti
        );

        rumbleIdParticipants[_rumbleId.current()].push(_tokenId);
        tokenToRumblesEntered[_tokenId].push(_rumbleId.current());
        addressToRumblesEntered[msg.sender].push(_rumbleId.current());

        return _rumbleId.current();
    }

    // fulfill chainlink VRF randomness, and run roll logic
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint256 rumbleId = responseIdToBattle[requestId].battleId;
        uint256 powerup = 0;

        if(responseIdToBattle[requestId].juicedUp > 0){
            powerup = (randomness % (responseIdToBattle[requestId].juicedUp * 9)) + responseIdToBattle[requestId].juicedUp;
        }

        uint powerlevel = IMaticMike(mmAddress).getPowerLevel(responseIdToBattle[requestId].tokenId) + powerup;
        address tokenHolder;

        // check if in gym and assign accordingly
        if(IMaticMike(mmAddress).ownerOf(responseIdToBattle[requestId].tokenId) != hghAddress){
            tokenHolder = IMaticMike(mmAddress).ownerOf(responseIdToBattle[requestId].tokenId);
        }
        else{
            tokenHolder = IHgh(hghAddress).getStaker(responseIdToBattle[requestId].tokenId);
        }
         

        uint256 roll = randomness % powerlevel;

        rumbleIdToRolls[rumbleId].push(
            RollInfo(
                responseIdToBattle[requestId].tokenId,
                tokenHolder,
                roll
            )
        );

        royaleProcessedLink[rumbleId]++;

        if(royaleProcessedLink[rumbleId] == royaleParticipants[rumbleId]){
            if(royaleParticipants[rumbleId] >= rumbleSize){
                beginDance(rumbleId);
            }
            else if(royaleParticipants[rumbleId] >= minimumSize && block.timestamp - royaleTimeTrigger[rumbleId] >= maxTime){
                beginDance(rumbleId);
            }
        }
    }

    function beginDance(uint256 rumbleId) internal{
        require(!battleIsComplete[rumbleId], "Battle already completed");

        RollInfo memory fpRoll;
        RollInfo memory spRoll;
        RollInfo memory tpRoll;

        // we should sort all the entries and create an array of structs from lowest to highest
        for(uint16 i=0; i<rumbleIdToRolls[rumbleId].length; i++){
            if(rumbleIdToRolls[rumbleId][i].roll > fpRoll.roll){
                tpRoll = spRoll;
                spRoll = fpRoll;
                fpRoll = rumbleIdToRolls[rumbleId][i];
            }
            else if(rumbleIdToRolls[rumbleId][i].roll == fpRoll.roll){
                tpRoll = spRoll;

                if(coinFlip(rumbleIdToRolls[rumbleId][i].tokenId, rumbleIdToRolls[rumbleId][i].holder, i) > 0){
                    spRoll = fpRoll;
                    fpRoll = rumbleIdToRolls[rumbleId][i];
                }
                else{
                    spRoll = rumbleIdToRolls[rumbleId][i];
                }
            }
            else if(rumbleIdToRolls[rumbleId][i].roll > spRoll.roll){
                tpRoll = spRoll;
                spRoll = rumbleIdToRolls[rumbleId][i];
            }
            else if(rumbleIdToRolls[rumbleId][i].roll == spRoll.roll){
                if(coinFlip(rumbleIdToRolls[rumbleId][i].tokenId, rumbleIdToRolls[rumbleId][i].holder, i) > 0){
                    tpRoll = spRoll;
                    spRoll = rumbleIdToRolls[rumbleId][i];
                }
                else{
                    tpRoll = rumbleIdToRolls[rumbleId][i];
                }
            }
            else if(rumbleIdToRolls[rumbleId][i].roll > tpRoll.roll){
                tpRoll = rumbleIdToRolls[rumbleId][i];
            }
            else if(rumbleIdToRolls[rumbleId][i].roll == tpRoll.roll && coinFlip(rumbleIdToRolls[rumbleId][i].tokenId, rumbleIdToRolls[rumbleId][i].holder, i) > 0){
                tpRoll = rumbleIdToRolls[rumbleId][i];
            }
        }

        uint256 totalPot = royalePot[rumbleId];
        uint256 tpPayout = totalPot * 1/10;
        uint256 spPayout = totalPot * 2/10;
        uint256 fpPayout = totalPot * 7/10;


        // we should have a internal struct that saves the top 3 placements
        battleIdToWinners[rumbleId].push(
            Winner(
                fpRoll.tokenId,
                1,
                rumbleId,
                fpPayout,
                fpRoll.holder
            )
        );

        battleIdToWinners[rumbleId].push(
            Winner(
                spRoll.tokenId,
                2,
                rumbleId,
                spPayout,
                spRoll.holder
            )
        );

        battleIdToWinners[rumbleId].push(
            Winner(
                tpRoll.tokenId,
                3,
                rumbleId,
                tpPayout,
                tpRoll.holder
            )
        );

        // increase rumbleid
        battleIsComplete[rumbleId] = true;

        _rumbleId.increment();
        royaleTimeTrigger[_rumbleId.current()] = block.timestamp;
        
        // payout winners
        IHgh(hghAddress).transfer(tpRoll.holder, tpPayout);
        IHgh(hghAddress).transfer(spRoll.holder, spPayout);
        IHgh(hghAddress).transfer(fpRoll.holder, fpPayout);
    }

    function coinFlip(uint256 _t, address _a, uint16 _c) internal view returns (uint8){
        return uint8(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.difficulty,
                            _t,
                            _a,
                            _c,
                            _rumbleId.current()
                        )
                    )
                ) % 2
            );
    }


    // analytics stuff
    function populateWinners(uint256 rumbleId) internal{
        for(uint8 i=0; i<battleIdToWinners[rumbleId].length; i++){
            tokenToWinner[battleIdToWinners[rumbleId][i].tokenId].push(battleIdToWinners[rumbleId][i]);
            addressToWinner[battleIdToWinners[rumbleId][i].holder].push(battleIdToWinners[rumbleId][i]);
            
            if(battleIdToWinners[rumbleId][i].placement == 1){
                firstPlacements.push(battleIdToWinners[rumbleId][i].tokenId);
                leaders.firstP = firstPlacements;
            }
            else  if(battleIdToWinners[rumbleId][i].placement == 2){
                secondPlacements.push(battleIdToWinners[rumbleId][i].tokenId);
                leaders.secondP = secondPlacements;
            }
            else if(battleIdToWinners[rumbleId][i].placement == 3){
                thirdPlacements.push(battleIdToWinners[rumbleId][i].tokenId);
                leaders.thirdP = thirdPlacements;
            }
        }
    }
}