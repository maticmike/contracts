// contracts/IDanceOff.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDanceOffLegacy {
    struct Winner{
        uint256 tokenId;
        uint8 placement;
        uint256 rumbleId;
        uint256 payout;
        address holder;
    }

    function getRumblesEntered(uint256 _tokenId) external view returns (uint256[] memory);
    function getPlacementsByToken(uint256 _tokenId) external view returns (Winner[] memory);
}