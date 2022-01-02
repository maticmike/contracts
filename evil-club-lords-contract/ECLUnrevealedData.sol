// contracts/ECLUnrevealedData.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./library/MaticMikeLibrary.sol";
import "./interface/IMaticMike.sol";
import "./interface/IMikeData.sol";
import "./interface/IECL.sol";

contract ECLUnrevealedData{
    // base64 structures
    struct Base{
        string styles;
        string background;
        string crowd;
    }

    Base encoded;
    // Addresses
    address _owner;
    address nullAddress = 0x0000000000000000000000000000000000000000;
    address mmAddress;
    address eclAddress;
    address dataAddress;

    constructor(){
        _owner = msg.sender;
    }

    /**
     * @dev Hash to metadata function
     */
    function hashToMetadata(uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        uint256 hoursLeft = (IECL(eclAddress).getHoursToReveal(_tokenId) / 60) / 60;
        uint16 mikeId = IECL(eclAddress).mintToMike(_tokenId);

        string memory metadataString;

        metadataString = string(
            abi.encodePacked(
                metadataString,
                '{"trait_type":"Hours Left","value":"',
                MaticMikeLibrary.toString(hoursLeft),
                '"},',
                '{"trait_type":"Matic Mike Staked","value":"#',
                MaticMikeLibrary.toString(mikeId),
                '"}'
            )
        );
        
        return string(abi.encodePacked("[", metadataString, "]"));
    }

    /**
     * @dev Hash to SVG function
     */
    function hashToSVG(uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        string memory hoursLeft = MaticMikeLibrary.toString((IECL(eclAddress).getHoursToReveal(_tokenId) / 60) / 60);
        uint16 mikeId = IECL(eclAddress).mintToMike(_tokenId);

        // pull mike graphic to a base 64
        string memory mikeSvg = IData(dataAddress).hashToSVG(IMaticMike(mmAddress)._tokenIdToHash(mikeId), mikeId);

        string memory svgString;

        svgString = string(
            abi.encodePacked(
                '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" id="Club" viewBox="0 0 96 96" shape-rendering="crispedges">',
                encoded.styles,
                encoded.background,
                '<image x="36" y="39" width="24" height="24" image-rendering="pixelated" preserveAspectRatio="xMidYMid" xlink:href="data:image/svg+xml;base64,',
                mikeSvg,
                '"/>',
                encoded.crowd,
                '<svg width="96" height="18px" x="0" y="3"><text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" style="font-size: 8px;fill: #fff;font-family: PixelFont;">',
                hoursLeft,
                ' Hours Remain</text></svg><svg width="96px" height="10px" x="0" y="75"><text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" style="font-size: 8px;fill: #fff;font-family: PixelFont;">#',
                MaticMikeLibrary.toString(mikeId),
                '</text></svg><svg width="96px" height="10px" x="0" y="83"><text x="50%" y="50%" dominant-baseline="middle" text-anchor="middle" style="font-size: 8px;fill: #fff;font-family: PixelFont;">On the stage!</text></svg></svg>'
            )
        );

        return MaticMikeLibrary.encode(bytes(svgString));
    }

    /*********************************
    *   Trait insertion functions
    **********************************/

    /**
     * @dev Add styles
     * @param _styles styles sheet with encoded font
     */
    function addStyles(string memory _styles)
        public
        onlyOwner
    {
        encoded.styles = string(abi.encodePacked(encoded.styles, _styles));
        return;
    }

    /**
     * @dev Add a background
     * @param _background styles sheet with encoded font
     */
    function addBG(string memory _background)
        public
        onlyOwner
    {

        encoded.background = string(abi.encodePacked(encoded.background, _background));
        return;
    }

    /**
     * @dev Add a crowd
     * @param _crowd styles sheet with encoded font
     */
    function addCrowd(string memory _crowd)
        public
        onlyOwner
    {
        encoded.crowd = string(abi.encodePacked(encoded.crowd, _crowd));

        return;
    }
    
    function setECLAddress(address _address) public onlyOwner{
        eclAddress = _address;
    }
    
    function setMmAddress(address _address) public onlyOwner{
        mmAddress = _address;
    }

    function setMmDataAddress(address _address) public onlyOwner{
        dataAddress = _address;
    }

    /**
     * @dev Modifier to only allow owner to call functions
     */
    modifier onlyOwner() {
        require(_owner == msg.sender);
        _;
    }
}