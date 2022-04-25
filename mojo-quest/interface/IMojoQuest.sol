// contracts/IMojoQuest.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";


interface IMojoQuest{    
    function getMojoBoost(uint16 _tokenId, address _address) external view returns (uint8);
}