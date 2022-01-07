// contracts/DanceOff.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IHgh.sol";
import "./interface/IMaticMike.sol";
import "./interface/IECL.sol";

contract DanceOff is VRFConsumerBase, Ownable{
    using Counters for Counters.Counter;
    Counters.Counter private _rumbleId;
    Counters.Counter private _pvpId;
    Counters.Counter private _challengeId;

    struct RollInfo{
        uint256 tokenId;
        address _contract;
        address holder;
        uint256 roll;
        uint256 powerLevel;
    }

    struct BattleType{
        uint8 battleType;
        uint256 battleId;
        uint256 tokenId;
        address _contract;
        uint8 juicedUp;
        uint256 wager;
    }

    struct Winner{
        uint256 tokenId;
        address _contract;
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

    struct Participants{
        uint256 tokenId;
        address _contract;
    }

    Participants[] public firstPlacements;
    Participants[] public secondPlacements;
    Participants[] public thirdPlacements;
    Participants[] public noPlacements;

    // Track participants
    mapping(uint256 => RollInfo[]) private rumbleIdToRolls;
    mapping(bytes32 => BattleType) private responseIdToBattle;
    
    mapping(uint256 => bool) internal battleIsComplete;
    mapping(uint256 => Winner[]) internal battleIdToWinners;
    mapping(uint256 => uint256) internal royaleTimeTrigger;
    mapping(uint256 => uint8) internal royaleParticipants;
    mapping(uint256 => uint8) internal royaleProcessedLink;
    mapping(uint256 => uint256) internal royalePot;

    mapping(address => bool) private addressToAllowed;
    mapping(address => bool) private addressHasPowerlevel;

    // add address
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) private tokenToRumble;
    
    // analytical stuff
    // need to add addresses to all these to account for ECL
    mapping(uint256 => mapping(address => uint256[])) tokenToRumblesEntered;
    mapping(uint256 => mapping(address => Winner[])) tokenToWinner;
    mapping(uint256 => Participants[]) rumbleIdParticipants;

    mapping(address => Winner[]) addressToWinner;
    mapping(address => uint256[]) addressToRumblesEntered;

    // Pricing 
    uint256 wagerMulti = 1000000000000000000;
    uint256 currentPrice = 1000000000000000000;
    uint8 rumbleSize = 50;
    uint8 minimumSize = 15;
    uint256 maxTime = 3600; // 1 hour trigger
    uint8 maxJuice = 5;

    uint256 SEED_NONCE = 0;

    // contract addresses
    address hghAddress;
    address mmAddress;
    address eclAddress;

    bytes32 private keyHash;
    uint256 private fee;

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
        VRFConsumerBase(0x8C7382F9D8f56b33781fE506E897a4F1e2d17255, 0x326C977E6efc84E512bB9C30f76E30c160eD06FB)
    {
        // Chainlink Info
        keyHash = 0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4;
        fee = 0.0001 * 10 ** 18; // 0.0001 LINK
        royaleTimeTrigger[_rumbleId.current()] = block.timestamp;
    }

    // owner functions set everything

    /**
     * @dev Set time trigger to start from this point
     */
    function setTimeTriggerNow() external onlyOwner{
        royaleTimeTrigger[_rumbleId.current()] = block.timestamp;
    }

    /**
     * @dev Set contract active
     */
    function setActive(bool _active) external onlyOwner{
        active = _active;
    }

    /**
     * @dev Set contract addresses
     * @param _hghAddress erc20 address
     * @param _mmAddress Matic Mike address
     * @param _eclAddress Evil Club Lords address
     */
    function setAddress(address _hghAddress, address _mmAddress, address _eclAddress) external onlyOwner{
        hghAddress = _hghAddress;
        mmAddress = _mmAddress;
        eclAddress = _eclAddress;
    }

    /**
     * @dev Set price for entry, goes directly to pot
     * @param _price price in wei
     */
    function setPrice(uint256 _price) external onlyOwner{
        currentPrice = _price;
    }

    /**
     * @dev Set rumble size
     * @param _size total amount of entries to rumble
     */
    function setRumbleSize(uint8 _size) external onlyOwner{
        rumbleSize = _size;
    }

    /**
     * @dev Set minimum size
     * @param _size minimum required for rumble to start
     */
    function setMinSize(uint8 _size) external onlyOwner{
        minimumSize = _size;
    }

    /**
     * @dev Set minimum size
     * @param _time time before rumble lowers max queue size to min
     */
    function setMaxTime(uint256 _time) external onlyOwner{
        maxTime = _time;
    }

    /**
     * @dev failsafe to pull out hgh and send back to users
     */
    function withdrawHghIfStuck() external onlyOwner{
        uint256 balance = IHgh(hghAddress).balanceOf(address(this));
        IHgh(hghAddress).transfer(msg.sender, balance);
    }

    /**
     * @dev If VRF fails due to gas we can force start queue
     * @param rumbleId ID for the rumble
     */
    function forceStart(uint256 rumbleId) external onlyOwner{

        uint256 _seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    rumbleIdToRolls[rumbleId][0].tokenId,
                    rumbleIdToRolls[rumbleId][0].holder,
                    SEED_NONCE
                )
            )
        ) % 10000;

        SEED_NONCE++;

        beginDance(rumbleId, _seed);
    }

    /**
     * @dev If link fee ever increases we can set it here
     * @param _fee chainlink fee for vrf
     */
    function setLinkFee(uint256 _fee) public onlyOwner{
        fee = _fee;
    }

    /**
     * @dev If link fee ever increases we can set it here
     * @param _maxJuice max additional HGH entries can add to increase powerlevel
     */
    function setMaxJuice(uint8 _maxJuice)public onlyOwner{
        maxJuice = _maxJuice;
    }

    /**
     * @dev Set all contracts allowed to enter this royale
     * @param _address address of contract (ERC721)
     * @param _allow true or false
     * @param _hasPowerLevel For ERC721 contracts that are not part of the MM family, we can set false.
     */
    function setAllowedContract(address _address, bool _allow, bool _hasPowerLevel) public onlyOwner{
        addressToAllowed[_address] = _allow;
        addressHasPowerlevel[_address] = _hasPowerLevel;
    }

    // end owner functions

    // // analytical stuff

    /**
     * @dev Get max juice
     */
    function getMaxJuice() public view returns (uint8){
        return maxJuice;
    }

    /**
     * @dev Get current rumble id
     */
    function getCurrentRumble() public view returns (uint256){
        return _rumbleId.current();
    }

    /**
     * @dev Get current total pot
     */
    function getCurrentPot() public view returns (uint256){
        return royalePot[_rumbleId.current()];
    }

    /**
     * @dev Get amount of participants
     */
    function getCurrentEntries() public view returns (uint8){
        return royaleParticipants[_rumbleId.current()];
    }
    
    /**
     * @dev Get the timer trigger for the current rumble
     */
    function getTimeTrigger() public view returns (uint256){
        return royaleTimeTrigger[_rumbleId.current()];
    }

    /**
     * @dev Get the size trigger from rumble
     * @param rumbleId id of the rumble to check
     */
    function getCurrentSizeTrigger(uint256 rumbleId) public view returns (uint8){
        if(block.timestamp - royaleTimeTrigger[rumbleId] >= maxTime){
            return minimumSize;
        }
        else{
            return rumbleSize;
        }
    }

    /**
     * @dev Check if rumble id is complete
     * @param rumbleId check if this rumble is complete
     */
    function isComplete(uint256 rumbleId) public view returns (bool){
        return battleIsComplete[rumbleId];
    }

    /**
     * @dev Check rumbles entered by token
     * @param _tokenId token of the NFT
     * @param _address address of the NFTs contract
     */
    function getRumblesEntered(uint256 _tokenId, address _address) public view returns (uint256[] memory){
        return tokenToRumblesEntered[_tokenId][_address];
    }

    /**
     * @dev Get placements of the token
     * @param _tokenId token of the NFT
     * @param _address address of the NFTs contract
     */
    function getPlacementsByToken(uint256 _tokenId, address _address) public view returns (Winner[] memory){
        return tokenToWinner[_tokenId][_address];
    }

    /**
     * @dev Get all wins by user address
     * @param _address address of the users wallet
     */
    function getPlacementsByAddress(address _address) public view returns (Winner[] memory){
        return addressToWinner[_address];
    }

    /**
     * @dev get Rumbles entered by address
     * @param _address address of the users wallet
     */
    function getRumblesEnteredByAddress(address _address) public view returns (uint256[] memory){
        return addressToRumblesEntered[_address];
    }

    /**
     * @dev Get placements by the rumble
     * @param rumbleId id of the rumble
     */
    function getPlacementsByRumble(uint256 rumbleId) public view returns (Winner[] memory){
        return battleIdToWinners[rumbleId];
    }

    /**
     * @dev Get entries of the rumble
     * @param rumbleId id of the rumble
     */
    function getEntriesByRumble(uint256 rumbleId) public view returns (Participants[] memory){
        return rumbleIdParticipants[rumbleId];
    }

    /**
     * @dev Get first places
     */
    function getFirstPlace() public view returns (Participants[] memory){
        return firstPlacements;
    }

    /**
     * @dev Get second places
     */
    function getSecondPlace() public view returns (Participants[] memory){
        return secondPlacements;
    }

    /**
     * @dev Get third places
     */
    function getThirdPlace() public view returns (Participants[] memory){
        return thirdPlacements;
    }

    // The Battle Royale Functions

    /**
     * @dev Enter the battle royale
     * @param _tokenId of the users NFT
     * @param _address of NFT contract
     * @param _hghJuice additional juice boost in ether ($HGH)
     */
    function enterRoyale(uint256 _tokenId, address _address, uint8 _hghJuice) public returns (uint256){
        require(active, "Dance Royale not currently active");
        require(_hghJuice <= maxJuice, "Over the maximum juice amount");
        require(IHgh(hghAddress).balanceOf(msg.sender) >= (_hghJuice * wagerMulti) + currentPrice, "Not enough HGH in wallet balance");
        require(addressToAllowed[_address], "This is not an allowed contract");

        // check in gym & club as well 
        if(_address == mmAddress){
            require(IMaticMike(mmAddress).ownerOf(_tokenId) == msg.sender || IHgh(hghAddress).getStaker(_tokenId) == msg.sender || IECL(eclAddress).getStaker(uint16(_tokenId)) == msg.sender, "Not the owner of token");
        }
        else{
            require(IECL(_address).ownerOf(_tokenId) == msg.sender || IHgh(hghAddress).expansionGetStaker(_address, _tokenId) == msg.sender, "Not the owner of this token");
            if(_address == eclAddress){
                require(IECL(_address).getHoursToReveal(_tokenId) == 0, "Not revealed, cannot enter royale until revealed");
            }
        }
        
        require(royaleParticipants[_rumbleId.current()] < rumbleSize && !battleIsComplete[_rumbleId.current()], "Royale trigger currently in progress. Try again in a minute");
        
        // require that they are not already entered in the competition...
        require(!tokenToRumble[_tokenId][_address][_rumbleId.current()], "Already entered in competition");

        // if new rumble populate analytics from previous rumble
        if(_rumbleId.current() != 0 && royaleParticipants[_rumbleId.current()] == 0){
            populateWinners(_rumbleId.current() - 1);
        }

        // The following order of operations prevents reentrancy from draining contract
        // burn the juiced up amount
        IHgh(hghAddress).burnFrom(msg.sender, _hghJuice * wagerMulti);

        // transfer HGH to contract
        IHgh(hghAddress).transferFrom(msg.sender, address(this), currentPrice);

        // begin royale entry
        royaleParticipants[_rumbleId.current()]++;
        royalePot[_rumbleId.current()] = royalePot[_rumbleId.current()] + wagerMulti;
        tokenToRumble[_tokenId][_address][_rumbleId.current()] = true;
        
        bytes32 requestId = requestRandomness(keyHash, fee);

        responseIdToBattle[requestId] = BattleType(
            1,
            _rumbleId.current(),
            _tokenId,
            _address,
            _hghJuice,
            wagerMulti
        );

        Participants memory participant;
        participant.tokenId = _tokenId;
        participant._contract = _address;

        rumbleIdParticipants[_rumbleId.current()].push(participant);
        tokenToRumblesEntered[_tokenId][_address].push(_rumbleId.current());
        addressToRumblesEntered[msg.sender].push(_rumbleId.current());

        return _rumbleId.current();
    }

    /**
     * @dev VRF Callback which stores seeds for roll calculation
     * @param requestId of the VRF callback
     * @param randomness the seed passed by chainlink
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint256 rumbleId = responseIdToBattle[requestId].battleId;
        uint256 powerup = 0;

        if(responseIdToBattle[requestId].juicedUp > 0){
            powerup = (randomness % (responseIdToBattle[requestId].juicedUp * 9)) + responseIdToBattle[requestId].juicedUp;
        }

        uint powerlevel;
        address tokenHolder;
        address curHolder;

        if(responseIdToBattle[requestId]._contract == mmAddress){
            powerlevel = IMaticMike(mmAddress).getPowerLevel(responseIdToBattle[requestId].tokenId) + powerup;

            curHolder = IMaticMike(mmAddress).ownerOf(responseIdToBattle[requestId].tokenId);
            // check if in gym and assign accordingly
            if(curHolder != hghAddress && curHolder!= eclAddress){
                tokenHolder = curHolder;
            }
            else if(curHolder == hghAddress){
                tokenHolder = IHgh(hghAddress).getStaker(responseIdToBattle[requestId].tokenId);
            }
            else if(curHolder == eclAddress){
                tokenHolder = IECL(eclAddress).getStaker(uint16(responseIdToBattle[requestId].tokenId));
            }
            
        }
        else if(addressHasPowerlevel[responseIdToBattle[requestId]._contract]){
            powerlevel = IECL(responseIdToBattle[requestId]._contract).getPowerLevel(responseIdToBattle[requestId].tokenId) + powerup;

            curHolder = IECL(responseIdToBattle[requestId]._contract).ownerOf(responseIdToBattle[requestId].tokenId);
            // check if in gym and assign accordingly
            if(curHolder != hghAddress){
                tokenHolder = curHolder;
            }
            else if(curHolder == hghAddress){
                tokenHolder = IHgh(hghAddress).expansionGetStaker(responseIdToBattle[requestId]._contract, responseIdToBattle[requestId].tokenId);
            }
        }
        else{
            tokenHolder = IERC721(responseIdToBattle[requestId]._contract).ownerOf(responseIdToBattle[requestId].tokenId);
            powerlevel = 395 + (randomness % 31) + powerup;
        }

        rumbleIdToRolls[rumbleId].push(
            RollInfo(
                responseIdToBattle[requestId].tokenId,
                responseIdToBattle[requestId]._contract,
                tokenHolder,
                randomness,
                powerlevel
            )
        );

        royaleProcessedLink[rumbleId]++;

        if(royaleProcessedLink[rumbleId] == royaleParticipants[rumbleId]){
            if(royaleParticipants[rumbleId] >= rumbleSize){
                beginDance(rumbleId, randomness % 10000);
            }
            else if(royaleParticipants[rumbleId] >= minimumSize && block.timestamp - royaleTimeTrigger[rumbleId] >= maxTime){
                beginDance(rumbleId, randomness % 10000);
            }
        }
    }

    /**
     * @dev Trigger to start the dance. A global seed modifier is passed so nobody an spy on seeds to estimate outcome.
     * @param rumbleId the rumble id to start
     * @param entropy the seed modifier for all seeds stored to provide true randoness in roll calculation
     */
    function beginDance(uint256 rumbleId, uint256 entropy) internal{
        require(!battleIsComplete[rumbleId], "Battle already completed");

        // aka battle is started
        battleIsComplete[rumbleId] = true;

        RollInfo memory fpRoll;
        RollInfo memory spRoll;
        RollInfo memory tpRoll;

        uint256 roll;

        // begin calculations of rolls and set first - third place
        for(uint16 i=0; i<rumbleIdToRolls[rumbleId].length; i++){
            roll = uint256(
                    keccak256(
                        abi.encodePacked(
                            rumbleIdToRolls[rumbleId][i].roll,
                            entropy
                        )
                    )
                ) % rumbleIdToRolls[rumbleId][i].powerLevel;

            if(roll > fpRoll.roll){
                tpRoll = spRoll;
                spRoll = fpRoll;
                fpRoll = rumbleIdToRolls[rumbleId][i];

                fpRoll.roll = roll;
            }
            else if(roll == fpRoll.roll){
                tpRoll = spRoll;

                if(coinFlip(rumbleIdToRolls[rumbleId][i].tokenId, rumbleIdToRolls[rumbleId][i].holder, i) > 0){
                    spRoll = fpRoll;
                    fpRoll = rumbleIdToRolls[rumbleId][i];
                    fpRoll.roll = roll;
                }
                else{
                    spRoll = rumbleIdToRolls[rumbleId][i];
                    spRoll.roll = roll;
                }
            }
            else if(roll > spRoll.roll){
                tpRoll = spRoll;
                spRoll = rumbleIdToRolls[rumbleId][i];

                spRoll.roll = roll;
            }
            else if(roll == spRoll.roll){
                if(coinFlip(rumbleIdToRolls[rumbleId][i].tokenId, rumbleIdToRolls[rumbleId][i].holder, i) > 0){
                    tpRoll = spRoll;
                    spRoll = rumbleIdToRolls[rumbleId][i];

                    spRoll.roll = roll;
                }
                else{
                    tpRoll = rumbleIdToRolls[rumbleId][i];
                    
                    tpRoll.roll = roll;
                }
            }
            else if(roll > tpRoll.roll){
                tpRoll = rumbleIdToRolls[rumbleId][i];

                tpRoll.roll = roll;
            }
            else if(roll == tpRoll.roll && coinFlip(rumbleIdToRolls[rumbleId][i].tokenId, rumbleIdToRolls[rumbleId][i].holder, i) > 0){
                tpRoll = rumbleIdToRolls[rumbleId][i];

                tpRoll.roll = roll;
            }
            entropy++;
        }

        uint256 totalPot = royalePot[rumbleId];
        uint256 tpPayout = totalPot * 1/10;
        uint256 spPayout = totalPot * 2/10;
        uint256 fpPayout = totalPot * 7/10;


        // we should have a internal struct that saves the top 3 placements
        battleIdToWinners[rumbleId].push(
            Winner(
                fpRoll.tokenId,
                fpRoll._contract,
                1,
                rumbleId,
                fpPayout,
                fpRoll.holder
            )
        );

        battleIdToWinners[rumbleId].push(
            Winner(
                spRoll.tokenId,
                spRoll._contract,
                2,
                rumbleId,
                spPayout,
                spRoll.holder
            )
        );

        battleIdToWinners[rumbleId].push(
            Winner(
                tpRoll.tokenId,
                tpRoll._contract,
                3,
                rumbleId,
                tpPayout,
                tpRoll.holder
            )
        );

        // increase rumbleid
        _rumbleId.increment();
        royaleTimeTrigger[_rumbleId.current()] = block.timestamp;
        
        // payout winners
        IHgh(hghAddress).transfer(tpRoll.holder, tpPayout);
        IHgh(hghAddress).transfer(spRoll.holder, spPayout);
        IHgh(hghAddress).transfer(fpRoll.holder, fpPayout);
    }

    /**
     * @dev a coin flip function for ties. This is too intricate, we can simplify the coin flip
     * @param _t token id used in randomness
     * @param _a address of the holder
     * @param _c an nonce used in the coin flip
     */
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

    /**
     * @dev Called by the first entry into the royale
     * @param rumbleId Rumble id of the previous rumble for population
     */
    function populateWinners(uint256 rumbleId) internal{
        for(uint8 i=0; i<battleIdToWinners[rumbleId].length; i++){
            tokenToWinner[battleIdToWinners[rumbleId][i].tokenId][battleIdToWinners[rumbleId][i]._contract].push(battleIdToWinners[rumbleId][i]);
            addressToWinner[battleIdToWinners[rumbleId][i].holder].push(battleIdToWinners[rumbleId][i]);
            
            Participants memory participant;

            participant.tokenId = battleIdToWinners[rumbleId][i].tokenId;
            participant._contract = battleIdToWinners[rumbleId][i]._contract;

            if(battleIdToWinners[rumbleId][i].placement == 1){
                firstPlacements.push(participant);
            }
            else if(battleIdToWinners[rumbleId][i].placement == 2){
                secondPlacements.push(participant);
            }
            else if(battleIdToWinners[rumbleId][i].placement == 3){
                thirdPlacements.push(participant);
            }
        }
    }
}