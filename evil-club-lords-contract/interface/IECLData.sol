// contracts/IECLData.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IECLData {
    function hashToMetadata(uint256 _tokenId) external view returns (string memory);
    function hashToSVG(uint256 _tokenId) external view returns (string memory);
    function getPowerLevel(uint256 _tokenId) external view returns (uint16);
}