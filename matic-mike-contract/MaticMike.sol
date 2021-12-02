// contracts/MaticMike.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./bridge/MaticMint.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBase.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IHgh.sol";
import "./interface/IMikeData.sol";
import "./library/MaticMikeLibrary.sol";

contract MaticMike is 
    ERC721Enumerable, 
    VRFConsumerBase, 
    IChildToken,
    AccessControlMixin,
    NativeMetaTransaction,
    ContextMixin,
    Ownable  {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");
    mapping (uint256 => bool) public withdrawnTokens;

    // limit batching of tokens due to gas limit restrictions
    uint256 public constant BATCH_LIMIT = 20;

    event WithdrawnBatch(address indexed user, uint256[] tokenIds);
    event TransferWithMetadata(address indexed from, address indexed to, uint256 indexed tokenId, bytes metaData);
/*
    Matic Mike is a unique fully decentralized NFT built on Polygon.

    Unique features include 
    - Upgrading your NFT all on-chain, possibly increasing your NFTs rarity.
    - We call this NFT Token Injection - Using an ERC20 to Inject Power into your NFT
    - PvE Features - Battling another contract to add undiscovered traits during initial mint.
    - Burn Rerolls and Staking Functionality - custom HGH token accompanying this contract.
    - PvP Features - An additional contract is being launched for wagering  and battling.
    - Power Levels - NFT traits include a power level association, which is used in the random
    number generation for PvE and PvP features. Higher power levels slightly increase outcome.
    - 100% on chain metadata and image generation, wagering, battling, and future functionality.
    - Launched on Polygon Network for gas costs associated with staking, minting, upgrading, PvP, 
    PvE and burn rerolls.
    - Chainlink VRF integration for upgrading for true verified random number generation
    - Multi-Contract design for on chain Data generation through multiple sources of contracts

    Portions of this contract for creating a metadata hash for initial trait setup
    are partially recycled from Anonymice. The code has been studied to be
    fully understood and expanded upon, and we have been transparent
    with Mouse Dev about using portions of his contract to build off of.

    Be sure to support us as well as other developers trying to 
    push the envelope and expand utility in blockchain as this is the 
    start of something much bigger than just a game.
*/

    using MaticMikeLibrary for uint8;

    // Mappings
    mapping(string => bool) hashToMinted;
    mapping(uint256 => string) internal tokenIdToHash;
    

    // Minting Maps
    mapping(address => uint256) purchased;
    mapping(address => bool) whitelist;

    // VRF and Staking Maps
    mapping(bytes32 => uint256) private requestIdToToken;
    
    // Booleans
    bool public active = false;
    bool public whitelistActive = false;
    bool public burnRerollActive = false;
    bool public donationActive = false;

    //uint256
    uint256 UPGRADE_CHANCE = 9349;
    uint256 UPGRADE_COST = 1000000000000000000;
    uint256 SEED_NONCE = 0;
    uint256 private fee;

    //uint8
    uint8 MAX_PER_WALLET = 10;

    // bytes32
    bytes32 private keyHash;

    //uint arrays
    uint16[][8] TIERS;

    //address
    address hghAddress;
    address iDataAddress;

    address _owner;
    address nullAddress = 0x0000000000000000000000000000000000000000;

    // Mainnet LINK
    // TOKEN        0xb0897686c545045aFc77CF20eC7A532E3120E0F1
    // Coordinator  0x3d2341ADb2D31f1c5530cDC622016af293177AE0
    // Key Hash     0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da

    // Mainnet PoS Bridge
    // Depositor 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa

    constructor() 
        VRFConsumerBase(0x3d2341ADb2D31f1c5530cDC622016af293177AE0, 0xb0897686c545045aFc77CF20eC7A532E3120E0F1)
        ERC721("Matic Mike", "MIKE")
    {
        _owner = msg.sender;
        _setupContractId("MikeMintableERC721");
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());

        _setupRole(DEPOSITOR_ROLE, 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa);
        _initializeEIP712("Matic Mike");

        // Chainlink Info
        keyHash = 0xf86195cf7690c55907b2b611ebb7343a6f649bff128701cc542f0569e2c549da;
        fee = 0.0001 * 10 ** 18; // 0.0001 LINK

        // Clothing
        TIERS[0] = [25, 75, 1000, 1400, 1500, 1750, 1750, 2500];
        // Eyes
        TIERS[1] = [50, 150, 750, 1250, 1350, 1450, 1666, 1666, 1668];
        // Hair
        TIERS[2] = [200, 250, 300, 500, 1050, 1925, 1925, 1925, 1925];
        // Mouth
        TIERS[3] = [200, 300, 1000, 1000, 2000, 2750, 2750];
        // Tattoos
        TIERS[4] = [150, 350, 500, 1500, 1500, 2500, 3500]; 
        // Earrings
        TIERS[5] = [50, 50, 100, 400, 450, 500, 700, 1800, 2000, 3500];
        // Nipple Rings
        TIERS[6] = [300, 800, 900, 1000, 1100, 5900];
        // Body
        TIERS[7] = [50, 100, 500, 1220, 1870, 1870, 1870, 2520];
    }

    /* POLYGON POS BRIDGE TO ALLOW TRANSFER OF TOKENS TO ETHEREUM MAINNET */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721Enumerable, AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _msgSender()
        internal
        override
        view
        returns (address sender)
    {
        return ContextMixin.msgSender();
    }

    /**
     * @notice called when token is deposited on root chain
     * @dev Should be callable only by ChildChainManager
     * Should handle deposit by minting the required tokenId(s) for user
     * Should set `withdrawnTokens` mapping to `false` for the tokenId being deposited
     * Minting can also be done by other functions
     * @param user user address for whom deposit is being done
     * @param depositData abi encoded tokenIds. Batch deposit also supported.
     */
    function deposit(address user, bytes calldata depositData)
        external
        override
        only(DEPOSITOR_ROLE)
    {

        // deposit single
        if (depositData.length == 32) {
            uint256 tokenId = abi.decode(depositData, (uint256));
            withdrawnTokens[tokenId] = false;
            _mint(user, tokenId);

        // deposit batch
        } else {
            uint256[] memory tokenIds = abi.decode(depositData, (uint256[]));
            uint256 length = tokenIds.length;
            for (uint256 i; i < length; i++) {
                withdrawnTokens[tokenIds[i]] = false;
                _mint(user, tokenIds[i]);
            }
        }

    }

    /**
     * @notice called when user wants to withdraw token back to root chain
     * @dev Should handle withraw by burning user's token.
     * Should set `withdrawnTokens` mapping to `true` for the tokenId being withdrawn
     * This transaction will be verified when exiting on root chain
     * @param tokenId tokenId to withdraw
     */
    function withdraw(uint256 tokenId) external {
        require(_msgSender() == ownerOf(tokenId), "ChildMintableERC721: INVALID_TOKEN_OWNER");
        withdrawnTokens[tokenId] = true;
        _burn(tokenId);
    }

    /**
     * @notice called when user wants to withdraw multiple tokens back to root chain
     * @dev Should burn user's tokens. This transaction will be verified when exiting on root chain
     * @param tokenIds tokenId list to withdraw
     */
    function withdrawBatch(uint256[] calldata tokenIds) external {

        uint256 length = tokenIds.length;
        require(length <= BATCH_LIMIT, "ChildMintableERC721: EXCEEDS_BATCH_LIMIT");

        // Iteratively burn ERC721 tokens, for performing
        // batch withdraw
        for (uint256 i; i < length; i++) {

            uint256 tokenId = tokenIds[i];

            require(_msgSender() == ownerOf(tokenId), string(abi.encodePacked("ChildMintableERC721: INVALID_TOKEN_OWNER ", tokenId)));
            withdrawnTokens[tokenId] = true;
            _burn(tokenId);

        }

        // At last emit this event, which will be used
        // in MintableERC721 predicate contract on L1
        // while verifying burn proof
        emit WithdrawnBatch(_msgSender(), tokenIds);

    }

    /**
     * @notice called when user wants to withdraw token back to root chain with token URI
     * @dev Should handle withraw by burning user's token.
     * Should set `withdrawnTokens` mapping to `true` for the tokenId being withdrawn
     * This transaction will be verified when exiting on root chain
     *
     * @param tokenId tokenId to withdraw
     */
    function withdrawWithMetadata(uint256 tokenId) external {

        require(_msgSender() == ownerOf(tokenId), "ChildMintableERC721: INVALID_TOKEN_OWNER");
        withdrawnTokens[tokenId] = true;

        // Encoding metadata associated with tokenId & emitting event
        emit TransferWithMetadata(ownerOf(tokenId), address(0), tokenId, this.encodeTokenMetadata(tokenId));

        _burn(tokenId);

    }

    /**
     * @dev This method is supposed to be called by client when withdrawing token with metadata
     * and pass return value of this function as second paramter of `withdrawWithMetadata` method
     * @param tokenId Token for which URI to be fetched
     */
    function encodeTokenMetadata(uint256 tokenId) external view virtual returns (bytes memory) {
        // Ethereum chain will pull MetaData live from Polygon
        return abi.encode(""); 
    }

    /**
     * @notice Example function to handle minting tokens on matic chain
     * @dev Minting can be done as per requirement,
     * This implementation allows only admin to mint tokens but it can be changed as per requirement
     * Should verify if token is withdrawn by checking `withdrawnTokens` mapping
     * @param user user for whom tokens are being minted
     * @param tokenId tokenId to mint
     */
    function mint(address user, uint256 tokenId) public only(DEFAULT_ADMIN_ROLE) {
        require(!withdrawnTokens[tokenId], "ChildMintableERC721: TOKEN_EXISTS_ON_ROOT_CHAIN");
        _mint(user, tokenId);
    }

    /* END POLYGON POS FUNCTIONS */

    /*

    Owner functions

    */

    /**
    * @dev Whitelist activation for a short time before sales activation
    */
    function activateWhitelist() public onlyOwner {
        whitelistActive = true;
        active = false;
    }

    /**
    * @dev Add to Whitelist
    */
    function addToWhitelist(address[] memory _whitelist) public onlyOwner {
        for(uint256 i=0; i<_whitelist.length; i++){
            whitelist[_whitelist[i]] = true;
        }
    }

    /**
    * @dev Sales activation setter. If any issues occur can flip it off.
    * @param val is true or false
    */
    function activateSale(bool val) public onlyOwner {
        whitelistActive = false;
        active = val;
    }

    /**
    * @dev Contract addresses set here. Interface will be the major contract added for dynamic integration in future.
    * @param _address is the address of the Contracts
    */

    function setHghAddress(address _address) public onlyOwner{
        hghAddress = _address;
    }

    function setIDataAddress(address _address) public onlyOwner{
        iDataAddress = _address;
    }

    /**
    * @dev Burn reroll activation
    * @param _roll is true or false
    * @param _donation is true or false
    */
    function activateRollAndDonation(bool _roll, bool _donation) public onlyOwner {
        burnRerollActive = _roll;
        donationActive = _donation;
    }

    /**
    * @dev Set upgrade cost if it's too low or high
    * @param amount is value in wei
    */
    function setUpgradeCost(uint256 amount) public onlyOwner {
        UPGRADE_COST = amount;
    }

    /*

    Minting, upgrades, and other public functions

    */

    /**
    * @dev public upgrade function that calls burns HGH and calls chainlink VRF
    * @param _tokenId is the NFT ID Number to be upgraded if successful.
    */
    function upgradeMike(uint256 _tokenId) public returns (bytes32){
        require(ownerOf(_tokenId) == msg.sender, "Sender not owner of supplied token");
        require(LINK.balanceOf(address(this)) >= fee, "Not enough LINK.");
        //burn current HGH cost for upgrade
        IHgh(hghAddress).burnFrom(msg.sender, UPGRADE_COST);
        
        bytes32 requestId = requestRandomness(keyHash, fee);
        requestIdToToken[requestId] = _tokenId;

        return requestId;
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
        // set to 0 for now for testing
        require((randomness % 10000) >= UPGRADE_CHANCE, "Bad roll, upgrade attempt failed");

        uint256 _traitRoll = (randomness % 8) + 1;

        string memory tokenHash = _tokenIdToHash(requestIdToToken[requestId]);

        uint8 thisTraitIndex = MaticMikeLibrary.parseInt(
            MaticMikeLibrary.substring(tokenHash, _traitRoll, _traitRoll + 1)
        );

        uint8 startIndex = 0;
        string memory newHash;

        if(thisTraitIndex > 0){
            if((randomness % thisTraitIndex) == 0 && thisTraitIndex > 1){
                startIndex = thisTraitIndex - 2;
            }
            else{
                startIndex = thisTraitIndex - 1;
            }
            

            while(true){
                // create new hash
                if(_traitRoll == 8){
                    newHash = string(abi.encodePacked(MaticMikeLibrary.substring(tokenHash, 0, 8), MaticMikeLibrary.toString(startIndex)));
                }
                else{
                    newHash = string(
                        abi.encodePacked(
                            MaticMikeLibrary.substring(tokenHash, 0, _traitRoll), 
                            MaticMikeLibrary.toString(startIndex), 
                            MaticMikeLibrary.substring(tokenHash, _traitRoll+1, 9)
                        )
                    );
                }

                // check if hash exists
                if (!hashToMinted[newHash]){
                    // successful mint. Update token hash and increase HGH cost to upgrade by 3
                    hashToMinted[tokenHash] = false;
                    tokenIdToHash[requestIdToToken[requestId]] = newHash;
                    hashToMinted[newHash] = true;
                    UPGRADE_COST = UPGRADE_COST + 3000000000000000000;
                    break;
                }
                else if(startIndex == 0){
                    // unsuccessful mint no mint
                    break;
                }
                else{
                    // continue to next tier of upgrade
                    startIndex--;
                }
            }
        }
    }

    /*

    Read Functions

    */

    /**
    * @dev Get whitelistActive
    */
    function isWhitelistActive() 
        public 
        view 
        returns (bool)
    {
        // interface to pull from MaticMikeData contract
        // pass in hash and tokenid
        return whitelistActive;
    }

    /**
    * @dev Get burnRerollActive
    * @param _address is to check if you're on whitelist.
    */
    function isOnWhitelist(address _address)
        public 
        view 
        returns (bool)
    {
        return whitelist[_address];
    }

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
    * @dev Get donationActive
    */
    function isDonationActive() 
        public 
        view 
        returns (bool)
    {
        // interface to pull from MaticMikeData contract
        // pass in hash and tokenid
        return donationActive;
    }

    /**
    * @dev Get upgrade cost
    */
    function getUpgradeCost() public view returns(uint256){
        return UPGRADE_COST;
    }

    /**
    * @dev Get total mints
    */
    function getTotalMints() public view returns(uint256){
        return _tokenIds.current();
    }

    /**
    * @dev Get Power Level by addition of trait power levels as well as external contracts
    * @param _tokenId token id of Matic Mike
    */
    function getPowerLevel(uint256 _tokenId) 
        public 
        view 
        returns (uint16)
    {
        // interface to pull from MaticMikeData contract
        // pass in hash and tokenid
        return IData(iDataAddress).getPowerLevel(tokenIdToHash[_tokenId], _tokenId);
    }

    /**
     * @dev Returns the SVG and metadata for a token Id for Ethereum Chain
     * @param _tokenId The tokenId to return the SVG and metadata for.
     */
    function getPosBridgeTokenURI(uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        require(bytes(tokenIdToHash[_tokenId]).length != 0, "Token not minted");
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    MaticMikeLibrary.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "Matic Mike #',
                                    MaticMikeLibrary.toString(_tokenId),
                                    '", "description": "This is the official Matic Mike Ethereum Bridge for the Matic Mike Club NFT on Polygon.", "image": "data:image/svg+xml;base64,',
                                    IData(iDataAddress).hashToSVG(tokenIdToHash[_tokenId], _tokenId),
                                    '","attributes":',
                                        IData(iDataAddress).hashToMetadata(tokenIdToHash[_tokenId], _tokenId),
                                    "}"
                                    )
                                )
                            )
                        )
                    )
                );
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

        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    MaticMikeLibrary.encode(
                        bytes(
                            string(
                                abi.encodePacked(
                                    '{"name": "Matic Mike #',
                                    MaticMikeLibrary.toString(_tokenId),
                                    '", "description": "Matic Mike is a collection of 10000 NFTs on the Polygon Chain with Ethereum Bridge. Fully on-chain.", "image": "data:image/svg+xml;base64,',
                                    IData(iDataAddress).hashToSVG(tokenIdToHash[_tokenId], _tokenId),
                                    '","attributes":',
                                        IData(iDataAddress).hashToMetadata(tokenIdToHash[_tokenId], _tokenId),
                                    "}"
                                    )
                                )
                            )
                        )
                    )
                );
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
                _randinput < currentLowerBound + thisPercentage
            ) return i.toString();
            currentLowerBound = currentLowerBound + thisPercentage;
        }
        revert();
    }

    /**
     * @dev Generates a 9 digit hash from a tokenId, address, and random number.
     * @param _t The token id to be used within the hash.
     * @param _a The address to be used within the hash.
     * @param _c The custom nonce to be used within the hash.
     */
    function hash(
        uint256 _t,
        address _a,
        uint256 _c
    ) internal returns (string memory) {
        require(_c < 10);

        string memory currentHash = "0";

        for (uint8 i = 0; i < 8; i++) {
            SEED_NONCE++;
            uint16 _randinput = uint16(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            block.timestamp,
                            block.difficulty,
                            _t,
                            _a,
                            _c,
                            SEED_NONCE
                        )
                    )
                ) % 10000
            );

            currentHash = string(
                abi.encodePacked(currentHash, rarityGen(_randinput, i))
            );
        }

        if (hashToMinted[currentHash]) return hash(_t, _a, _c + 1);

        return currentHash;
    }

    /**
     * @dev Returns the current HGH cost for minting
     */
    function currentHghCost() public view returns (uint256) {
        if (_tokenIds.current() >= 2500 && _tokenIds.current() <= 4000)
            return 1000000000000000000;
        if (_tokenIds.current() > 4000 && _tokenIds.current() <= 6000)
            return 2000000000000000000;
        if (_tokenIds.current() > 6000 && _tokenIds.current() <= 8000)
            return 3000000000000000000;
        if (_tokenIds.current() > 8000 && _tokenIds.current() <= 10000)
            return 4000000000000000000;

        revert();
    }

    /**
     * @dev Mint internal, can be used in donation mint and HGH mint
     */
    function mintInternal() internal {
        require(_tokenIds.current() < 10000);
        require(!MaticMikeLibrary.isContract(msg.sender));

        tokenIdToHash[_tokenIds.current()] = hash(_tokenIds.current(), msg.sender, 0);

        hashToMinted[tokenIdToHash[_tokenIds.current()]] = true;
        purchased[msg.sender] = purchased[msg.sender] + 1;
        
        _mint(msg.sender, _tokenIds.current());
        _tokenIds.increment();
    }

    /**
     * @dev Mints new tokens.
     */
    function mintMike() public {
        if (msg.sender != _owner) {
            require(active, "Sale is not active currently.");
            require(purchased[msg.sender] + 1 <= MAX_PER_WALLET, "Only 10 mints per wallet allowed");
        }
        
        require(_tokenIds.current() < 10000, "Total supply exceeded.");
        if (_tokenIds.current() < 2500) return mintInternal();

        IHgh(hghAddress).burnFrom(msg.sender, currentHghCost());

        return mintInternal();
    }

    /**
     * @dev Mints new tokens with 50 MATIC donation
     */
    function donationMint() public payable {
        if (msg.sender != _owner) {
            require(active, "Sale is not active currently.");
        }
        require(purchased[msg.sender] + 1 <= MAX_PER_WALLET, "Only 10 mints per wallet allowed");
        require(_tokenIds.current() < 10000, "Total supply exceeded.");
        require(donationActive, "Donation Mint not yet Active");

        require(50000000000000000000 == msg.value, "Insuffient amount sent.");

        return mintInternal();
    }

    /**
     * @dev 1 Mint per whitelist
     */
    function whitelistMint() public{
        require(whitelistActive, "Whitelist is not active currently.");
        require(_tokenIds.current() < 10000, "Total supply exceeded.");
        require(whitelist[msg.sender], "You are not on the whitelist");

        whitelist[msg.sender] = false;
        return mintInternal();
    }

    /**
     * @dev Burns and mints new.
     * @param _tokenId The token to burn.
     */
    function burnForMint(uint256 _tokenId) public {
        require(ownerOf(_tokenId) == msg.sender);
        require(burnRerollActive, "Burn rerolls not currently active");
        require(_tokenIds.current() < 10000, "No mints left.");

        //Burn token
        _transfer(
            msg.sender,
            0x000000000000000000000000000000000000dEaD,
            _tokenId
        );

        mintInternal();
    }

    /**
     * @dev Sends contract balance to owner
     */
    function withdrawAll() public payable onlyOwner {
        (bool success, ) = payable(msg.sender).call{
            value: address(this).balance
        }("");
        require(success, "Failed to send Ether");
    }
}