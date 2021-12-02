// contracts/IHgh.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IData {
    function hashToMetadata(string memory _hash, uint256 _tokenId) external view returns (string memory);
    function hashToSVG(string memory _hash, uint256 _tokenId) external view returns (string memory);
    function getPowerLevel(string memory _hash, uint256 _tokenId) external view returns (uint16);
}