// contracts/MojoQuest.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./chainlink/VRFConsumerBaseUpgradeable.sol";
import "./interface/IHgh.sol";
import "./interface/IMaticMike.sol";
import "./interface/IECL.sol";

contract MojoQuestV3 is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable, VRFConsumerBaseUpgradeable{
    using CountersUpgradeable for CountersUpgradeable.Counter;
    CountersUpgradeable.Counter private _questId;

    // locations
    struct Location{
        uint8 minMojo;
        uint8 hghCost;
        uint8[4] reward;
        uint16[4] rewardChance;
    }

    struct Participant{
        uint256 tokenId;
        address _contract;
    }

    mapping(uint256 => Location) public locations;

    // response to quest id
    mapping(bytes32 => uint256) private responseToQuest;

    // questid tracks 2 participants entered
    mapping(uint256 => Participant[]) private questToParticipants;
    mapping(uint256 => uint256) private questToLocation;

    // store the info for easy return
    mapping(uint256 => mapping(address => uint256)) private tokenToQuest;
    mapping(uint256 => mapping(address => uint256)) private tokenToTimer;
    mapping(uint256 => mapping(address => uint8)) private tokenToEntries;

    // mojo booster
    mapping(uint256 => mapping(address => uint8)) public mojoBoost;

    uint256 SEED_NONCE;

    uint8 mmQuestsPerDay;
    uint8 eclQuestsPerDay;

    // contract addresses
    address hghAddress;
    address mmAddress;
    address eclAddress;

    bytes32 private keyHash;
    uint256 private fee;

    bool public active;

    event QuestStarted(address owner, uint256 questId, uint256 timestamp);
    event QuestEnded(uint256 questId, uint256 tokenId, address tokenContract, uint8 reward);

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

    function initialize() initializer public{
        __VRFConsumerBase_init(0x8C7382F9D8f56b33781fE506E897a4F1e2d17255, 0x326C977E6efc84E512bB9C30f76E30c160eD06FB);
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __UUPSUpgradeable_init_unchained();

        // Chainlink Info
        keyHash = 0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4;
        fee = 0.0001 * 10 ** 18; // 0.0001 LINK

        mmQuestsPerDay = 5;
        eclQuestsPerDay = 1;

        // set locations
        Location memory clubLux = Location({
            minMojo: 0,
            hghCost: 7,
            reward: [4, 3, 2, 1],
            rewardChance: [600, 700, 1200, 7500]
        });

        Location memory clubPure = Location({
            minMojo: 4,
            hghCost: 9,
            reward: [7, 6, 5, 0],
            rewardChance: [550, 1450, 8000, 0]
        });

        Location memory clubSeven = Location({
            minMojo: 7,
            hghCost: 11,
            reward: [10, 9, 8, 0],
            rewardChance: [500, 1100, 8400, 0]
        });

        Location memory clubSin = Location({
            minMojo: 10,
            hghCost: 12,
            reward: [13, 12, 11, 0],
            rewardChance: [400, 900, 8700, 0]
        });

        Location memory clubXtra = Location({
            minMojo: 13,
            hghCost: 17,
            reward: [16, 15, 14, 0],
            rewardChance: [300, 700, 9000, 0]
        });

        Location memory clubSixnine = Location({
            minMojo: 16,
            hghCost: 50,
            reward: [20, 19, 18, 17],
            rewardChance: [50, 150, 300, 9500]
        });
        
        locations[0] = clubLux;
        locations[1] = clubPure;
        locations[2] = clubSeven;
        locations[3] = clubSin;
        locations[4] = clubXtra;
        locations[5] = clubSixnine;
    }

    // owner functions set everything

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

    function setQuestsPerDay(uint8 _mmQuests, uint8 _eclQuests) external onlyOwner{
        mmQuestsPerDay = _mmQuests;
        eclQuestsPerDay = _eclQuests;
    }

    /**
     * @dev failsafe to pull out token and send back to users
     */
    function withdrawBalance() external onlyOwner{
        uint256 balance = IERC20(hghAddress).balanceOf(address(this));
        IERC20(hghAddress).transfer(msg.sender, balance);
    }

    // end owner functions

    function questsLeft(uint256 tokenId, address _contract) public view returns (uint8){
        if(_contract == eclAddress){
            if(block.timestamp - tokenToTimer[tokenId][_contract] >= 86400){
                return eclQuestsPerDay;
            }
            else{
                return 0;
            }
        }
        else if(_contract == mmAddress){
             if(block.timestamp - tokenToTimer[tokenId][_contract] >= 86400){
                return mmQuestsPerDay;
            }
            else if(tokenToEntries[tokenId][_contract] < mmQuestsPerDay){
                return mmQuestsPerDay - tokenToEntries[tokenId][_contract];
            }
            else{
                return 0;
            }
        }
        else{
            return 0;
        }
    }

    function timeToReset(uint256 tokenId, address _contract) public view returns (uint256){
        if(block.timestamp - tokenToTimer[tokenId][_contract] < 86400){
            return 86400 - (block.timestamp - tokenToTimer[tokenId][_contract]);
        }
        else{
            return 0;
        }
    }

    // The Questing Fucntion

    /**
     * @dev Enter the quest. These require functions should be replaced with some custom errors to reduce gas and combine some logic.
     * @param _locationId location of the entry
     * @param _tokenOne of the users NFT
     * @param _tokenOneContract of NFT contract
     * @param _tokenTwo of the users NFT
     * @param _tokenTwoContract of NFT contract
     */
    function sendToQuest(uint256 _locationId, uint256 _tokenOne, address _tokenOneContract, uint256 _tokenTwo, address _tokenTwoContract) external nonReentrant{
        require(active, "Questing not currently active");
        require(_tokenTwoContract == eclAddress, "Evil Club Lord Must be Token Two");
        Location memory loc = locations[_locationId];

        require(loc.hghCost > 0, "Location doesn't exist");

        // check balance and send
        // require(IHgh(hghAddress).balanceOf(msg.sender) >= costofentry, "Insufficient balance.");
        // check in gym & club as well 
        if(_tokenOneContract == mmAddress){
            require(IMaticMike(mmAddress).ownerOf(_tokenOne) == msg.sender || IHgh(hghAddress).getStaker(_tokenOne) == msg.sender || IECL(eclAddress).getStaker(uint16(_tokenOne)) == msg.sender, "Not the owner of token");
            require(block.timestamp - tokenToTimer[_tokenOne][_tokenOneContract] >= 86400 || tokenToEntries[_tokenOne][_tokenOneContract] < mmQuestsPerDay, "Maxed out on questing for the day");
        }
        else{
            // this will need to change for external contracts that use their own staking contract
            require(IECL(eclAddress).ownerOf(_tokenOne) == msg.sender || IHgh(hghAddress).expansionGetStaker(_tokenOneContract, _tokenOne) == msg.sender, "Not the owner of this token");
            require(IECL(eclAddress).getHoursToReveal(_tokenOne) == 0, "Not revealed, cannot enter quest until revealed");
            require(block.timestamp - tokenToTimer[_tokenOne][_tokenOneContract] >= 86400 || tokenToEntries[_tokenOne][_tokenOneContract] < eclQuestsPerDay, "Maxed out on questing for the day");
        }

        // token two has to be ecl
        require(IECL(eclAddress).ownerOf(_tokenTwo) == msg.sender || IHgh(hghAddress).expansionGetStaker(_tokenTwoContract, _tokenTwo) == msg.sender, "Not the owner of this token");
        require(IECL(eclAddress).getHoursToReveal(_tokenTwo) == 0, "Not revealed, cannot enter quest until revealed");
        require(block.timestamp - tokenToTimer[_tokenTwo][_tokenTwoContract] >= 86400 || tokenToEntries[_tokenTwo][_tokenTwoContract] < eclQuestsPerDay, "Maxed out on questing for the day");

        
        // make sure both tokens are not on campaign
        require(tokenToQuest[_tokenOne][_tokenOneContract] == 0 && tokenToQuest[_tokenTwo][_tokenTwoContract] == 0, "Already on quest");

        // make sure token 1 has sufficient mojo boost
        require(loc.minMojo <= mojoBoost[_tokenOne][_tokenOneContract], "Your alpha token must meet the minimum MoJo boost requirement.");

        uint256 cost = loc.hghCost * 1 ether;
        require(IHgh(hghAddress).balanceOf(msg.sender) >= cost && cost > 0, "Insufficient balance or invalid location");
        // burn a portion of entry and collect a portion
        IHgh(hghAddress).burnFrom(msg.sender, cost * 1/4);
        IHgh(hghAddress).transferFrom(msg.sender, address(this), cost * 3/4);
        

        // begin quest
        _startQuest(_locationId, msg.sender, _tokenOne, _tokenOneContract, _tokenTwo, _tokenTwoContract);
    }

    function _startQuest(uint256 _locationId, address mikeOwner, uint256 _tokenOne, address _tokenOneContract, uint256 _tokenTwo, address _tokenTwoContract) internal{
        // send to quest emit event
        uint256 currentQuest = _questId.current();

        tokenToQuest[_tokenOne][_tokenOneContract] = currentQuest;
        tokenToQuest[_tokenTwo][_tokenTwoContract] = currentQuest;
        
        // set mappings
        if(block.timestamp - tokenToTimer[_tokenOne][_tokenOneContract] >= 86400){
            tokenToTimer[_tokenOne][_tokenOneContract] = block.timestamp;
            tokenToEntries[_tokenOne][_tokenOneContract] = 1;
        }
        else{
            tokenToEntries[_tokenOne][_tokenOneContract]++;
        }

        if(block.timestamp - tokenToTimer[_tokenTwo][_tokenTwoContract] >= 86400){
            tokenToTimer[_tokenTwo][_tokenTwoContract] = block.timestamp;
            tokenToEntries[_tokenTwo][_tokenTwoContract] = 1;
        }
        else{
            tokenToEntries[_tokenTwo][_tokenTwoContract]++;
        }

        tokenToQuest[_tokenOne][_tokenOneContract] = currentQuest;
        tokenToQuest[_tokenTwo][_tokenTwoContract] = currentQuest;

        questToParticipants[currentQuest].push(Participant({
            tokenId: _tokenOne,
            _contract: _tokenOneContract
        }));

        questToParticipants[currentQuest].push(Participant({
            tokenId: _tokenTwo,
            _contract: _tokenTwoContract
        }));

        questToLocation[currentQuest] = _locationId;
        bytes32 requestId = requestRandomness(keyHash, fee);
        responseToQuest[requestId] = currentQuest;

        _questId.increment();
        emit QuestStarted(mikeOwner, currentQuest, block.timestamp);
    }

    /**
     * @dev VRF Callback which stores seeds for roll calculation. Frontend-will read response and pull the winner into view with their new gfx
     * @param requestId of the VRF callback
     * @param randomness the seed passed by chainlink
     */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        uint256 currentQuest = responseToQuest[requestId];

        uint8 reward = getReward(questToLocation[currentQuest], randomness%10000);
        uint8 winnerIndex = getWinner(currentQuest, randomness);

        Participant[] memory entry = questToParticipants[currentQuest];
        // set token mojo boost, delete mapping to quest, emit winner information
        mojoBoost[entry[winnerIndex].tokenId][entry[winnerIndex]._contract] = reward;

        delete tokenToQuest[entry[0].tokenId][entry[0]._contract];
        delete tokenToQuest[entry[1].tokenId][entry[1]._contract];

        emit QuestEnded(currentQuest, questToParticipants[currentQuest][winnerIndex].tokenId, questToParticipants[currentQuest][winnerIndex]._contract, reward);
    }

    function getWinner(uint256 currentQuest, uint256 seed) internal view returns (uint8){
        uint16 rollOne = uint16(_rand(1, seed) % IMaticMike(questToParticipants[currentQuest][0]._contract).getPowerLevel(questToParticipants[currentQuest][0].tokenId));
        uint16 rollTwo = uint16(_rand(2, seed) % IMaticMike(questToParticipants[currentQuest][1]._contract).getPowerLevel(questToParticipants[currentQuest][1].tokenId));

        if(rollOne >= rollTwo){
            return 0;
        }
        else{
            return 1;
        }
    }

    function getReward(uint256 _locationId, uint256 _randinput) internal view returns(uint8){
        uint16 currentLowerBound = 0;
        for (uint8 i = 0; i < locations[_locationId].rewardChance.length; i++) {
            uint16 thisPercentage = locations[_locationId].rewardChance[i];
            if (
                _randinput >= currentLowerBound &&
                _randinput < currentLowerBound + thisPercentage
            ) return locations[_locationId].reward[i];
            currentLowerBound = currentLowerBound + thisPercentage;
        }
        revert();
    }

    function getMojoBoost(uint16 tokenId, address addr) public view returns(uint8){
        return mojoBoost[tokenId][addr];
    }

    function _rand(uint256 _entropy, uint256 seed) internal pure returns(uint256){
        return uint256(keccak256(abi.encode(seed, _entropy)));
    }

    // UUPS
    function _authorizeUpgrade(address) internal override onlyOwner {}
}