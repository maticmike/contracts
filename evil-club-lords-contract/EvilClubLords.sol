// contracts/EvilClubLords.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./interface/IHgh.sol";
import "./interface/IECLData.sol";
import "./library/MaticMikeLibrary.sol";

contract EvilClubLords is 
    ERC721Enumerable, 
    VRFConsumerBase, 
    Ownable  {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    using MaticMikeLibrary for uint8;

    // Mappings
    mapping(string => bool) hashToMinted;
    mapping(uint256 => string) internal tokenIdToHash;
    mapping(uint256 => bool) internal tokenIsBurnReroll;
    mapping(uint256 => uint8) internal tokenIdToBurns;
    mapping(uint256 => uint256) internal tokenIdToTime;
    mapping(uint256 => uint256) internal tokenIdToTimeStamp;
    mapping(uint16 => uint256[]) internal mikeToMint;
    mapping(uint256 => uint16) public mintToMike;
    mapping(uint16 => address) internal tokenIdToStaker;
    mapping(address => uint16[]) internal stakerToTokenIds;
    mapping(uint256 => uint256) internal lastInject;

    // VRF and Staking Maps
    mapping(bytes32 => uint256) private requestIdToToken;

    // In case a fulfill is reverted and we need an admin override
    mapping(uint256 => bytes32) private tokenToRequestId;

    // Booleans
    bool public active = false;
    bool public burnRerollActive = false;

    //uint256
    uint256 REROLL_COST = 10000000000000000000;
    uint256 SEED_NONCE = 0;
    uint256 private fee;
    uint256 MIN_TIME = 1209600;

    uint8 MAX_BURNS = 10;

    // bytes32
    bytes32 private keyHash;

    //uint arrays
    uint16[][8] TIERS;

    //address
    address hghAddress;
    address mikeAddress;
    address revealAddress;
    address unrevealedAddress;

    address _owner;
    address nullAddress = 0x0000000000000000000000000000000000000000;

    // Mainnet LINK
    // TOKEN        0xb0897686c545045aFc77CF20eC7A532E3120E0F1
    // Coordinator  0x3d2341ADb2D31f1c5530cDC622016af293177AE0
    // Key Hash     0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da

    // Mumbai LINK
    // TOKEN        0x326C977E6efc84E512bB9C30f76E30c160eD06FB
    // Coordinator  0x8C7382F9D8f56b33781fE506E897a4F1e2d17255
    // Key Hash     0x6e75b569a01ef56d18cab6a8e71e6600d6ce853834d4a5748b720d06f878b3a4

    constructor() 
        VRFConsumerBase(0x3d2341ADb2D31f1c5530cDC622016af293177AE0, 0xb0897686c545045aFc77CF20eC7A532E3120E0F1)
        ERC721("Evil Club Lords (Matic Mike)", "ECL")
    {
        _owner = msg.sender;

        // Chainlink Info
        keyHash = 0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da;
        fee = 0.0001 * 10 ** 18; // 0.0001 LINK

        // necklace
        TIERS[7] = [25, 75, 1000, 1400, 1500, 1750, 1750, 2500];
        // Eyes
        TIERS[6] = [50, 150, 750, 1250, 1500, 1750, 2000, 2550];
        // back
        TIERS[5] = [50, 250, 300, 500, 1050, 1925, 1925, 1925, 2075];
        // Mouth
        TIERS[4] = [200, 250, 300, 500, 1050, 1925, 1925, 1925, 1925];
        // Tattoos
        TIERS[3] = [100, 300, 500, 600, 600, 1000, 1000, 1950, 1950, 2000]; 
        // crown
        TIERS[2] = [50, 500, 2000, 3500, 3950];
        // Nipple Rings
        TIERS[1] = [300, 800, 900, 1000, 1100, 1100, 4800];
        // Body
        TIERS[0] = [375, 425, 600, 1220, 1770, 1870, 1870, 1870];
    }

    /*
    Owner functions
    */

    /**
    * @dev Sales activation setter. If any issues occur can flip it off.
    * @param val is true or false
    */
    function activateSale(bool val) public onlyOwner {
        active = val;
    }

    /**
    * @dev Contract addresses set here. Interface will be the major contract added for dynamic integration in future.
    * @param _hghAddress HGH Contract
    * @param _mikeAddress Matic Mike Contract
    * @param _dataAddress Unrevealed Data Contract
    * @param _revealAddress Revealed Data Contract
    */
    function setContractAddresses(address _hghAddress, address _mikeAddress, address _dataAddress, address _revealAddress) public onlyOwner{
        hghAddress = _hghAddress;
        mikeAddress = _mikeAddress;
        unrevealedAddress = _dataAddress;
        revealAddress = _revealAddress;
    }

    /**
    * @dev Set minimum time to reveal
    * @param _time seconds of time
    */
    function setMinTime(uint256 _time) public onlyOwner{
        MIN_TIME = _time;
    }

    /**
    * @dev Burn reroll activation
    * @param _roll is true or false
    */
    function activateBurn(bool _roll) public onlyOwner {
        burnRerollActive = _roll;
    }

    /**
    * @dev Admin override in case a fulfillRandomness call fails and we need to replace
    * @param _tokenId is the token to override
    */
    function forceFullfill(uint256 _tokenId) public onlyOwner{
        uint256 _seed = uint256(
            keccak256(
                abi.encodePacked(
                    block.timestamp,
                    block.difficulty,
                    _tokenId,
                    ownerOf(_tokenId),
                    SEED_NONCE
                )
            )
        );

        if(tokenIsBurnReroll[_tokenId] == false){
            tokenIdToTime[_tokenId] = MIN_TIME + (_seed % MIN_TIME);
        }
        
        // generate dna
        tokenIdToHash[_tokenId] = hash(_seed);
        hashToMinted[tokenIdToHash[_tokenId]] = true;
    }

    /*
    Internal Functions
    */

    /**
    * @dev Fulfills chainlink VRF. Upgrade Attempt.
    * @param requestId is the chainlink request id
    * @param randomness is the uint256 random number we will work off of.
    */
    function fulfillRandomness(bytes32 requestId, uint256 randomness) internal override {
        // check if a burn reroll, if so, no need to calculate time to reveal
        uint256 _tokenId = requestIdToToken[requestId];

        if(tokenIsBurnReroll[_tokenId] == false){
            tokenIdToTime[_tokenId] = MIN_TIME + (randomness % MIN_TIME);
        }
        
        // generate dna
        tokenIdToHash[_tokenId] = hash(randomness);
        hashToMinted[tokenIdToHash[_tokenId]] = true;
    }

    /*
    Read Functions
    */

    /**
    * @dev Get burnRerollActive
    */
    function isBurnRerollActive() 
        public 
        view 
        returns (bool)
    {
        // interface to pull from MaticMikeData contract
        // pass in hash and tokenid
        return burnRerollActive;
    }

    /**
    * @dev Get total mints
    */
    function getTotalMints() public view returns(uint256){
        return _tokenIds.current();
    }

    /**
    * @dev Get time to reveal
    * @param _tokenId token ID of the ECL
    */
    function getHoursToReveal(uint256 _tokenId) public view returns(uint256){
        if(block.timestamp - tokenIdToTimeStamp[_tokenId] > tokenIdToTime[_tokenId]){
            return 0;
        }
        else{
            return tokenIdToTime[_tokenId] - (block.timestamp - tokenIdToTimeStamp[_tokenId]);
        }
    }
    
    /**
     * @dev Gets the staker address
     * @param tokenId the token id of the Matic Mike
     */
    function getStaker(uint16 tokenId) public view returns (address) {
        return tokenIdToStaker[tokenId];
    }

    /**
     * @dev Gets the tokens of the staker
     * @param staker address of the staker
     */
    function getTokensStaked(address staker)
        public
        view
        returns (uint16[] memory)
    {
        return stakerToTokenIds[staker];
    }

    /**
     * @dev Hours Left on Stake by ID
     * @param tokenId hours left on the stake
     */
    function getHoursLeftOnStake(uint16 tokenId) public view returns (uint256){
        uint256 timeLeft = 0;

        for(uint256 i = 0; i < mikeToMint[tokenId].length; i++){
            timeLeft += getHoursToReveal(mikeToMint[tokenId][i]);
        }

        return timeLeft;
    }

    /**
    * @dev Get time until next injection to reduce hours
    * @param _tokenId token id of ECL
    */
    function getTimeUntilNextInject(uint256 _tokenId) public view returns (uint256){
        uint256 timeSinceInject = block.timestamp - lastInject[_tokenId];
        if(getHoursToReveal(_tokenId) == 0){
            return 99999;
        }
        else{
            if(timeSinceInject >= 86400){
                return 0;
            }
            else{
                return (86400 - timeSinceInject);
            }
        }
    }

    /**
    * @dev Get Power Level by addition of trait power levels as well as external contracts
    * @param _tokenId token id of ECL
    */
    function getPowerLevel(uint256 _tokenId) 
        public 
        view 
        returns (uint16)
    {
        require(getHoursToReveal(_tokenId) == 0, "Not yet revealed");
        return IECLData(revealAddress).getPowerLevel(_tokenId);
    }

    /**
    * @dev Get Burn Rerolls Left
    * @param _tokenId token id of ECL
    */
    function getBurnsLeft(uint256 _tokenId)
        public
        view
        returns (uint8){
        return (10 - tokenIdToBurns[_tokenId]);
    }

    /**
     * @dev Returns the SVG and metadata for a token Id
     * @param _tokenId The tokenId to return the SVG and metadata for.
     */
    function tokenURI(uint256 _tokenId)
        public
        view
        override
        returns (string memory)
    {
        require(_exists(_tokenId));

        if(getHoursToReveal(_tokenId) == 0 && bytes(tokenIdToHash[_tokenId]).length != 0){
            return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    MaticMikeLibrary.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "Evil Club Lord #',
                                    MaticMikeLibrary.toString(_tokenId),
                                    '", "description": "Matic Mike: Evil Club Lords is a collection with a total circulating supply of 5274 summoned by dancing your Matic Mike in the club. No IPFS, No API, all on-chain.", "image": "data:image/svg+xml;base64,',
                                    IECLData(revealAddress).hashToSVG(_tokenId),
                                    '","attributes":',
                                    IECLData(revealAddress).hashToMetadata(_tokenId),
                                    "}"
                                    )
                                )
                            )
                        )
                    )
                );
        }
        else{
            return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    MaticMikeLibrary.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "Evil Club Lord #',
                                    MaticMikeLibrary.toString(_tokenId),
                                    '", "description": "Matic Mike: Evil Club Lords is a collection with a total circulating supply of 5274 summoned by dancing your Matic Mike in the club. No IPFS, No API, all on-chain.", "image": "data:image/svg+xml;base64,',
                                    IECLData(unrevealedAddress).hashToSVG(_tokenId),
                                    '","attributes":',
                                    IECLData(unrevealedAddress).hashToMetadata(_tokenId),
                                    "}"
                                    )
                                )
                            )
                        )
                    )
                );
        }
    }

    /**
     * @dev Returns a hash for a given tokenId
     * @param _tokenId The tokenId to return the hash for.
     */
    function _tokenIdToHash(uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        require(getHoursToReveal(_tokenId) == 0, "Not yet revealed");
        string memory tokenHash = tokenIdToHash[_tokenId];
        //If this is a burned token, override the previous hash
        if (ownerOf(_tokenId) == 0x000000000000000000000000000000000000dEaD) {
            tokenHash = string(
                abi.encodePacked(
                    "1",
                    MaticMikeLibrary.substring(tokenHash, 1, 9)
                )
            );
        }

        return tokenHash;
    }

    /**
     * @dev Returns the wallet of a given wallet. Mainly for ease for frontend devs.
     * @param _wallet The wallet to get the tokens of.
     */
    function walletOfOwner(address _wallet)
        public
        view
        returns (uint256[] memory)
    {
        uint256 tokenCount = balanceOf(_wallet);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_wallet, i);
        }
        return tokensId;
    }

    /*
    Mint Functions
    */

     /**
     * @dev Converts a digit from 0 - 10000 into its corresponding rarity based on the given rarity tier.
     *      PUTS power level (10000-rarity) into the power level for token id which will be used to calculate
     *      battles. 
     * @param _randinput The input from 0 - 10000 to use for rarity gen.
     * @param _rarityTier The tier to use.
     */
    function rarityGen(uint256 _randinput, uint8 _rarityTier)
        internal
        view
        returns (string memory)
    {
        uint16 currentLowerBound = 0;
        for (uint8 i = 0; i < TIERS[_rarityTier].length; i++) {
            uint16 thisPercentage = TIERS[_rarityTier][i];
            if (
                _randinput >= currentLowerBound &&
                _randinput <= currentLowerBound + thisPercentage
            ) return i.toString();
            currentLowerBound = currentLowerBound + thisPercentage;
        }
        revert();
    }

    /**
     * @dev Generates a 9 digit hash from a seed generated by vrf
     * @param _seed The token id to be used within the hash.
     */
    function hash(
        uint256 _seed
    ) internal returns (string memory) {
        string memory currentHash = "0";

        for (uint8 i = 0; i < 8; i++) {
            SEED_NONCE++;
            uint16 _randinput = uint16(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            _seed,
                            SEED_NONCE
                        )
                    )
                ) % 10000
            );

            currentHash = string(
                abi.encodePacked(currentHash, rarityGen(_randinput, i))
            );
        }

        if (hashToMinted[currentHash]) return hash(_seed + 1);

        return currentHash;
    }

    /*
    Minting, and other public functions
    */

    /**
     * @dev Returns the current HGH cost for minting
     */
    function currentHghCost(uint16 _tokenId) public view returns (uint256) {
        if(mikeToMint[_tokenId].length == 0){
            return 25000000000000000000;
        }
        else if(mikeToMint[_tokenId].length == 1){
            return 50000000000000000000;
        }
        // max 2 mikes per mint
        revert();
    }

    /**
     * @dev Mint internal, called after staking Matic Mike in the club
     */
    function mintInternal() internal {
        require(!MaticMikeLibrary.isContract(msg.sender));

        uint256 currentId = _tokenIds.current();
        tokenIdToTimeStamp[_tokenIds.current()] = block.timestamp;
        tokenIdToTime[_tokenIds.current()] = 9999999;
        
        _mint(msg.sender, _tokenIds.current());
        _tokenIds.increment();

        bytes32 requestId = requestRandomness(keyHash, fee);
        requestIdToToken[requestId] = currentId;
    }

    /**
     * @dev burn internal, called when a token is burned
     * @param _tokenId ID of the token being burned
     */
    function burnInternal(uint256 _tokenId) internal {
        require(!MaticMikeLibrary.isContract(msg.sender));

        uint256 currentId = _tokenIds.current();
        tokenIdToTimeStamp[_tokenIds.current()] = block.timestamp;
        tokenIdToTime[_tokenIds.current()] = 0;
        tokenIsBurnReroll[_tokenIds.current()] = true;
        tokenIdToBurns[_tokenIds.current()] = tokenIdToBurns[_tokenId] + 1;

        _mint(msg.sender, _tokenIds.current());
        _tokenIds.increment();

        bytes32 requestId = requestRandomness(keyHash, fee);
        requestIdToToken[requestId] = currentId;
    }

    /**
     * @dev mintLord is the minting function for Evil Club Lords
     * @param _tokenId The Matic Mike Token Id being staked
     */
    function mintLord(uint16 _tokenId) public{
        if (msg.sender != _owner) {
            require(active, "Sale is not active currently.");
        }
        require(IERC721(mikeAddress).ownerOf(_tokenId) == msg.sender, "Not the owner of the token id.");
        require(mikeToMint[_tokenId].length < 2, "Max mints for this Matic Mike");

        IHgh(hghAddress).burnFrom(msg.sender, currentHghCost(_tokenId));
        
        tokenIdToStaker[_tokenId] = msg.sender;
        stakerToTokenIds[msg.sender].push(_tokenId);
        
        IERC721(mikeAddress).transferFrom(
            msg.sender,
            address(this),
            _tokenId
        );

        mikeToMint[_tokenId].push(_tokenIds.current());
        mintToMike[_tokenIds.current()] = _tokenId;

        mintInternal();
    }

    /**
     * @dev Burns and mints new.
     * @param _tokenId The token to burn.
     */
    function burnForMint(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender);
        require(burnRerollActive, "Burn rerolls not currently active");
        require(getHoursToReveal(_tokenId) == 0, "Not yet revealed.");
        require(tokenIdToBurns[_tokenId] < 10, "No burns left for this ECL.");

        //Burn HGH
        IHgh(hghAddress).burnFrom(msg.sender, 10000000000000000000);

        //Burn token
        _transfer(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            _tokenId
        );

        burnInternal(_tokenId);
    }

    /**
     * @dev Burns and mints new.
     * @param _amount Amount of HGH to inject.
     * @param _tokenId The token to burn.
     */
    function injectHGH(uint256 _amount, uint256 _tokenId) public{
        require(ownerOf(_tokenId) == msg.sender, "You don't own this token");
        require(_amount > 0 && _amount <= 10, "Can only inject up to 10 HGH a day");
        require(block.timestamp - lastInject[_tokenId] >= 86400, "Last inject was less than 24 hours ago");
        require(getHoursToReveal(_tokenId) > 0, "Already Revealed");
        
        uint256 burnAmount = _amount * 1000000000000000000;
        IHgh(hghAddress).burnFrom(msg.sender, burnAmount);

        if(tokenIdToTime[_tokenId] > (_amount * 3600)){
            tokenIdToTime[_tokenId] = tokenIdToTime[_tokenId] - (_amount * 3600);
        }
        else{
            tokenIdToTime[_tokenId] = 0;
        }

        lastInject[_tokenId] = block.timestamp;
    }

    /*
        Staking functions
    */

    function remove(address staker, uint256 index) internal {
        if (index >= stakerToTokenIds[staker].length) return;

        for (uint256 i = index; i < stakerToTokenIds[staker].length - 1; i++) {
            stakerToTokenIds[staker][i] = stakerToTokenIds[staker][i + 1];
        }
        stakerToTokenIds[staker].pop();
    }


    function removeTokenIdFromStaker(address staker, uint256 tokenId) internal {
        for (uint256 i = 0; i < stakerToTokenIds[staker].length; i++) {
            if (stakerToTokenIds[staker][i] == tokenId) {
                //This is the tokenId to remove;
                remove(staker, i);
            }
        }
    }

    /**
     * @dev unstake by IDs
     * @param tokenIds the tokens we are withdrawing
     */
    function unstakeByIds(uint16[] memory tokenIds) public {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenIdToStaker[tokenIds[i]] == msg.sender,
                "Message Sender was not original staker!"
            );


            for(uint256 j = 0; j < mikeToMint[tokenIds[i]].length; j++){
                require(getHoursToReveal(mikeToMint[tokenIds[i]][j]) == 0, "Still time left on reveal.");
            }

            IERC721(mikeAddress).transferFrom(
                address(this),
                msg.sender,
                tokenIds[i]
            );

            removeTokenIdFromStaker(msg.sender, tokenIds[i]);

            tokenIdToStaker[tokenIds[i]] = nullAddress;
        }
    }
}