// contracts/IDanceOff.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IDanceOff {
    struct Winner{
        uint256 tokenId;
        address _contract;
        uint8 placement;
        uint256 rumbleId;
        uint256 payout;
        address holder;
    }

    function getRumblesEntered(uint256 _tokenId, address _address) external view returns (uint256[] memory);
    function getPlacementsByToken(uint256 _tokenId, address _address) external view returns (Winner[] memory);
}