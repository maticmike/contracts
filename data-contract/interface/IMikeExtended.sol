// contracts/IMikeExtended.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";


interface IMikeExtended is IERC721Enumerable {
    // Struct it returns
    struct Traits {
        string traitName;
        string traitType;
        string pixels;
        uint256 pixelCount;
        uint8 powerLevel;
        bool valid;
    }
    
    /** @dev Gets the boss loot trait type and image string as well as pixel count (0-3)
    *   @param tokenId of the Matic Mike
    */
    function getAllPlayerLoot(uint256 tokenId) external view returns (Traits[] memory);
    
    /** @dev Gets the boss loot power level as an integer
    *   @param tokenId of the Matic Mike
    */
    function getLootPowerLevel(uint256 tokenId) external view returns (uint16);
}
