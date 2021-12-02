// contracts/Hgh.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import "./bridge/IMintableERC20.sol";

contract Hgh is 
    ERC20Burnable, 
    Ownable,
    IChildToken,
    AccessControlMixin,
    NativeMetaTransaction,
    ContextMixin {
/*
    Rupees contract using Cheeth as a blueprint. We love Anonymice.
    Contract functions for staking heroes to earn rupees to use for
    boss fights, upgrades, and eventually Apprentice training, and upgrades.
*/

    using SafeMath for uint256;

    bytes32 public constant DEPOSITOR_ROLE = keccak256("DEPOSITOR_ROLE");

    uint256 public MAX_WALLET_STAKED = 10;
    uint256 public EMISSIONS_RATE = 11574070000000;
    uint256 public CLAIM_END_TIME = 1641013200;
    uint256 public MAX_RESERVE = 100000;

    address nullAddress = 0x0000000000000000000000000000000000000000;

    address public contractAddress;

    //Mapping of hero to timestamp
    mapping(uint256 => uint256) internal tokenIdToTimeStamp;

    //Mapping of hero to staker
    mapping(uint256 => address) internal tokenIdToStaker;

    //Mapping of staker to heroes
    mapping(address => uint256[]) internal stakerToTokenIds;

    // expansion maps
    mapping(address => uint256) internal emissionsRate;
    mapping(address => mapping(uint256 => uint256)) internal expansionTokenIdToTimestamp;
    mapping(address => mapping(uint256 => address)) internal expansionTokenIdToStaker;
    mapping(address => mapping(address => uint256[])) internal expansionStakerToTokenIds;

    // Proxy
    // Mainnet: 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa
    constructor() ERC20("Matic Mike Juice", "HGH") {
        _setupContractId("HGHMintableERC20");
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(DEPOSITOR_ROLE, 0xA6FA4fB5f76172d178d61B04b0ecd319C5d1C0aa);
        _initializeEIP712('Matic Mike Juice');
    }

    /* Polygon PoS Bridge Functions */
    function _msgSender()
        internal
        override
        view
        returns (address sender)
    {
        return ContextMixin.msgSender();
    }

    function deposit(address user, bytes calldata depositData)
        external
        override
        only(DEPOSITOR_ROLE)
    {
        uint256 amount = abi.decode(depositData, (uint256));
        _mint(user, amount);
    }

    function withdraw(uint256 amount) external {
        _burn(_msgSender(), amount);
        
    }

    /* End Polygon PoS Bridge Functions */

    function setContractAddress(address _contractAddress) public onlyOwner {
        contractAddress = _contractAddress;
        return;
    }

    function setClaimEndTime(uint256 _endTime) public onlyOwner{
        CLAIM_END_TIME = _endTime;
    }

    function setExpansionEmission(address _contractAddress, uint256 _emissionsRate) public onlyOwner{
        emissionsRate[_contractAddress] = _emissionsRate;
    }

    function expansionGetTokensStaked(address _expansionAddress, address _staker) public
        view
        returns (uint256[] memory){

        return expansionStakerToTokenIds[_expansionAddress][_staker];
    }

    function getTokensStaked(address staker)
        public
        view
        returns (uint256[] memory)
    {
        return stakerToTokenIds[staker];
    }

    function expansionRemove(address _expansionAddress, address staker, uint256 index) internal{
        if (index >= expansionStakerToTokenIds[_expansionAddress][staker].length) return;

        for (uint256 i = index; i < expansionStakerToTokenIds[_expansionAddress][staker].length - 1; i++) {
            expansionStakerToTokenIds[_expansionAddress][staker][i] = expansionStakerToTokenIds[_expansionAddress][staker][i + 1];
        }

        expansionStakerToTokenIds[_expansionAddress][staker].pop();
    }

    function remove(address staker, uint256 index) internal {
        if (index >= stakerToTokenIds[staker].length) return;

        for (uint256 i = index; i < stakerToTokenIds[staker].length - 1; i++) {
            stakerToTokenIds[staker][i] = stakerToTokenIds[staker][i + 1];
        }
        stakerToTokenIds[staker].pop();
    }

    function expansionRemoveTokenIdFromStaker(address _expansionAddress, address staker, uint256 tokenId) internal {
        for (uint256 i = 0; i < expansionStakerToTokenIds[_expansionAddress][staker].length; i++) {
            if (expansionStakerToTokenIds[_expansionAddress][staker][i] == tokenId) {
                //This is the tokenId to remove;
                expansionRemove(_expansionAddress, staker, i);
            }
        }
    }

    function removeTokenIdFromStaker(address staker, uint256 tokenId) internal {
        for (uint256 i = 0; i < stakerToTokenIds[staker].length; i++) {
            if (stakerToTokenIds[staker][i] == tokenId) {
                //This is the tokenId to remove;
                remove(staker, i);
            }
        }
    }

    function expansionStakeByIds(address _expansionAddress, uint256[] memory tokenIds) public{
        require(emissionsRate[_expansionAddress] > 0, "Not our contract");
        require(
            expansionStakerToTokenIds[_expansionAddress][msg.sender].length + tokenIds.length <=
                MAX_WALLET_STAKED,
            "Must have less than 10 heroes from each contract staked!"
        );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                IERC721(_expansionAddress).ownerOf(tokenIds[i]) == msg.sender &&
                    expansionTokenIdToStaker[_expansionAddress][tokenIds[i]] == nullAddress,
                "Token must be stakable by you!"
            );

            IERC721(_expansionAddress).transferFrom(
                msg.sender,
                address(this),
                tokenIds[i]
            );

            expansionStakerToTokenIds[_expansionAddress][msg.sender].push(tokenIds[i]);

            expansionTokenIdToTimestamp[_expansionAddress][tokenIds[i]] = block.timestamp;
            expansionTokenIdToStaker[_expansionAddress][tokenIds[i]] = msg.sender;
        }
    }

    function stakeByIds(uint256[] memory tokenIds) public {
        require(
            stakerToTokenIds[msg.sender].length + tokenIds.length <=
                MAX_WALLET_STAKED,
            "Must have less than 10 heroes staked!"
        );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                IERC721(contractAddress).ownerOf(tokenIds[i]) == msg.sender &&
                    tokenIdToStaker[tokenIds[i]] == nullAddress,
                "Token must be stakable by you!"
            );

            IERC721(contractAddress).transferFrom(
                msg.sender,
                address(this),
                tokenIds[i]
            );

            stakerToTokenIds[msg.sender].push(tokenIds[i]);

            tokenIdToTimeStamp[tokenIds[i]] = block.timestamp;
            tokenIdToStaker[tokenIds[i]] = msg.sender;
        }
    }

    function unstakeAll() public {
        require(
            stakerToTokenIds[msg.sender].length > 0,
            "Must have at least one token staked!"
        );
        uint256 totalRewards = 0;

        for (uint256 i = stakerToTokenIds[msg.sender].length; i > 0; i--) {
            uint256 tokenId = stakerToTokenIds[msg.sender][i - 1];

            IERC721(contractAddress).transferFrom(
                address(this),
                msg.sender,
                tokenId
            );

            totalRewards =
                totalRewards +
                ((block.timestamp - tokenIdToTimeStamp[tokenId]) *
                    EMISSIONS_RATE);

            removeTokenIdFromStaker(msg.sender, tokenId);

            tokenIdToStaker[tokenId] = nullAddress;
        }

        _mint(msg.sender, totalRewards);
    }

    function expansionUnstakeByIds(address _expansionAddress, uint256[] memory tokenIds) public {
        require(emissionsRate[_expansionAddress] > 0, "Not our contract");
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                expansionTokenIdToStaker[_expansionAddress][tokenIds[i]] == msg.sender,
                "Message Sender was not original staker!"
            );

            IERC721(_expansionAddress).transferFrom(
                address(this),
                msg.sender,
                tokenIds[i]
            );

            totalRewards =
                totalRewards +
                ((block.timestamp - expansionTokenIdToTimestamp[_expansionAddress][tokenIds[i]]) *
                    emissionsRate[_expansionAddress]);

            expansionRemoveTokenIdFromStaker(_expansionAddress, msg.sender, tokenIds[i]);

            expansionTokenIdToStaker[_expansionAddress][tokenIds[i]] = nullAddress;
        }

        _mint(msg.sender, totalRewards);
    }

    function unstakeByIds(uint256[] memory tokenIds) public {
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenIdToStaker[tokenIds[i]] == msg.sender,
                "Message Sender was not original staker!"
            );

            IERC721(contractAddress).transferFrom(
                address(this),
                msg.sender,
                tokenIds[i]
            );

            totalRewards =
                totalRewards +
                ((block.timestamp - tokenIdToTimeStamp[tokenIds[i]]) *
                    EMISSIONS_RATE);

            removeTokenIdFromStaker(msg.sender, tokenIds[i]);

            tokenIdToStaker[tokenIds[i]] = nullAddress;
        }

        _mint(msg.sender, totalRewards);
    }

    function expansionClaimByTokenId(address _expansionAddress, uint256 tokenId) public {
        require(emissionsRate[_expansionAddress] > 0, "Not our contract");
        require(
            expansionTokenIdToStaker[_expansionAddress][tokenId] == msg.sender,
            "Token is not claimable by you!"
        );
        require(block.timestamp < CLAIM_END_TIME, "Claim period is over!");

        _mint(
            msg.sender,
            ((block.timestamp - expansionTokenIdToTimestamp[_expansionAddress][tokenId]) * emissionsRate[_expansionAddress])
        );

        expansionTokenIdToTimestamp[_expansionAddress][tokenId] = block.timestamp;
    }

    function claimByTokenId(uint256 tokenId) public {
        require(
            tokenIdToStaker[tokenId] == msg.sender,
            "Token is not claimable by you!"
        );
        require(block.timestamp < CLAIM_END_TIME, "Claim period is over!");

        _mint(
            msg.sender,
            ((block.timestamp - tokenIdToTimeStamp[tokenId]) * EMISSIONS_RATE)
        );

        tokenIdToTimeStamp[tokenId] = block.timestamp;
    }

    function expansionClaimAll(address _expansionAddress) public {
        require(emissionsRate[_expansionAddress] > 0, "Not our contract");
        require(block.timestamp < CLAIM_END_TIME, "Claim period is over!");
        uint256[] memory tokenIds = expansionStakerToTokenIds[_expansionAddress][msg.sender];
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                expansionTokenIdToStaker[_expansionAddress][tokenIds[i]] == msg.sender,
                "Token is not claimable by you!"
            );

            totalRewards =
                totalRewards +
                ((block.timestamp - expansionTokenIdToTimestamp[_expansionAddress][tokenIds[i]]) *
                    emissionsRate[_expansionAddress]);

            expansionTokenIdToTimestamp[_expansionAddress][tokenIds[i]] = block.timestamp;
        }

        _mint(msg.sender, totalRewards);
    }

    function claimAll() public {
        require(block.timestamp < CLAIM_END_TIME, "Claim period is over!");
        uint256[] memory tokenIds = stakerToTokenIds[msg.sender];
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            require(
                tokenIdToStaker[tokenIds[i]] == msg.sender,
                "Token is not claimable by you!"
            );

            totalRewards =
                totalRewards +
                ((block.timestamp - tokenIdToTimeStamp[tokenIds[i]]) *
                    EMISSIONS_RATE);

            tokenIdToTimeStamp[tokenIds[i]] = block.timestamp;
        }

        _mint(msg.sender, totalRewards);
    }

    function expansionGetAllRewards(address _expansionAddress, address staker) public view returns (uint256) {
        require(emissionsRate[_expansionAddress] > 0, "Not our contract");
        uint256[] memory tokenIds = expansionStakerToTokenIds[_expansionAddress][staker];
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalRewards =
                totalRewards +
                ((block.timestamp -  expansionTokenIdToTimestamp[_expansionAddress][tokenIds[i]]) *
                   emissionsRate[_expansionAddress]);
        }

        return totalRewards;
    }

    function getAllRewards(address staker) public view returns (uint256) {
        uint256[] memory tokenIds = stakerToTokenIds[staker];
        uint256 totalRewards = 0;

        for (uint256 i = 0; i < tokenIds.length; i++) {
            totalRewards =
                totalRewards +
                ((block.timestamp - tokenIdToTimeStamp[tokenIds[i]]) *
                    EMISSIONS_RATE);
        }

        return totalRewards;
    }

    function expansionGetRewardsByTokenId(address _expansionAddress, uint256 tokenId)
        public
        view
        returns (uint256)
    {
        require(emissionsRate[_expansionAddress] > 0, "Not our contract");
        require(
            expansionTokenIdToStaker[_expansionAddress][tokenId] != nullAddress,
            "Token is not staked!"
        );

        uint256 secondsStaked = block.timestamp - expansionTokenIdToTimestamp[_expansionAddress][tokenId];

        return secondsStaked * emissionsRate[_expansionAddress];
    }

    function getRewardsByTokenId(uint256 tokenId)
        public
        view
        returns (uint256)
    {
        require(
            tokenIdToStaker[tokenId] != nullAddress,
            "Token is not staked!"
        );

        uint256 secondsStaked = block.timestamp - tokenIdToTimeStamp[tokenId];

        return secondsStaked * EMISSIONS_RATE;
    }

    function expansionGetStaker(address _expansionAddress, uint256 tokenId) public view returns (address) {
        require(emissionsRate[_expansionAddress] > 0, "Not our contract");
        return expansionTokenIdToStaker[_expansionAddress][tokenId];
    }

    function getStaker(uint256 tokenId) public view returns (address) {
        return tokenIdToStaker[tokenId];
    }
}