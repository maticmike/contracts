// contracts/MatikMikeData.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./library/MaticMikeLibrary.sol";
import "./interface/IMikeExtended.sol";
import "./interface/IMaticMike.sol";
import "./interface/IECL.sol";
import "./interface/IDanceOff.sol";

contract ECLData{
    // Trait structure
    struct Trait{
        string traitName;
        string traitType;
        string pixels;
        uint256 pixelCount;
        uint8 powerLevel;
    }

    // lets make a map to svg for the body bg at trait index
    mapping(uint256 => string) bodyMap;

    // Trait Types
    mapping(uint256 => Trait[]) public traitTypes;

    // Addresses
    address _owner;
    address nullAddress = 0x0000000000000000000000000000000000000000;
    address mmAddress;
    address eclAddress;
    address dataAddress;
    address xxlAddress;
    address danceoffAddress;
    
    constructor(){
        _owner = msg.sender;
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
        string memory _hash;
        uint16 power;

        _hash = IECL(eclAddress)._tokenIdToHash(_tokenId);

        // read through traits
        for (uint8 i = 0; i < 9; i++) {
            uint8 thisTraitIndex = MaticMikeLibrary.parseInt(
                MaticMikeLibrary.substring(_hash, i, i + 1)
            );

            power = power + traitTypes[i][thisTraitIndex].powerLevel;
        }

        // pull power from other contracts
        if(xxlAddress != nullAddress){
            power = power + IMikeExtended(xxlAddress).getLootPowerLevel(_tokenId);
        }

        return power;
    }

    /**
     * @dev Hash to metadata function
     */
    function hashToMetadata(uint256 _tokenId)
        public
        view
        returns (string memory)
    {
        string memory metadataString;
        string memory _hash;

        _hash = IECL(eclAddress)._tokenIdToHash(_tokenId);
        uint16 pl;
        

        for (uint8 i = 0; i < 9; i++) {
            uint8 thisTraitIndex = MaticMikeLibrary.parseInt(
                MaticMikeLibrary.substring(_hash, i, i + 1)
            );

            metadataString = string(
                abi.encodePacked(
                    metadataString,
                    '{"trait_type":"',
                    traitTypes[i][thisTraitIndex].traitType,
                    '","value":"',
                    traitTypes[i][thisTraitIndex].traitName,
                    '"}'
                )
            );

            pl = pl + traitTypes[i][thisTraitIndex].powerLevel;

            if (i != 8)
                metadataString = string(abi.encodePacked(metadataString, ","));
        }

        
        // external contract call for expansion loot & graphics
        if(xxlAddress != nullAddress){
            IMikeExtended.Traits[] memory XxlTraits = IMikeExtended(xxlAddress).getAllPlayerLoot(_tokenId);

            for(uint256 i=0; i < XxlTraits.length; i++){
                if(XxlTraits[i].valid){
                    metadataString = string(abi.encodePacked(metadataString, ","));

                    if(keccak256(abi.encodePacked(XxlTraits[i].displayType)) == keccak256(abi.encodePacked("string"))){
                        metadataString = string(
                        abi.encodePacked(
                                metadataString,
                                '{"trait_type":"',
                                XxlTraits[i].traitType,
                                '","value":',
                                XxlTraits[i].traitName,
                                '}'
                            )
                        );
                    }
                    else{
                        metadataString = string(
                        abi.encodePacked(
                                metadataString,
                                '{"display_type":"', 
                                XxlTraits[i].displayType, 
                                '","trait_type":"',
                                XxlTraits[i].traitType,
                                '","value":',
                                XxlTraits[i].traitName,
                                '}'
                            )
                        );
                    }

                    pl = pl + XxlTraits[i].powerLevel;
                }
            }
        }
        
        metadataString = string(abi.encodePacked(metadataString, ","));
        metadataString = string(
            abi.encodePacked(
                metadataString,
                '{"trait_type":"Power Level","value":',
                MaticMikeLibrary.toString(pl),
                '}'
            )
        );

        // Dance Off Stats
        if(danceoffAddress != nullAddress){
            uint256 entered;
            uint256 placed;

            IDanceOff.Winner[] memory Winners = IDanceOff(danceoffAddress).getPlacementsByToken(_tokenId);
            entered = IDanceOff(danceoffAddress).getRumblesEntered(_tokenId).length;

            if(entered > 0 && Winners.length > 0){
                placed = MaticMikeLibrary.getPercent(Winners.length, entered);
            }
            metadataString = string(abi.encodePacked(metadataString, ","));
            metadataString = string(
                abi.encodePacked(
                    metadataString,
                    '{"display_type":"number","trait_type":"Dance Royales Entered","value":',
                    MaticMikeLibrary.toString(entered),
                    '}'
                )
            );
            metadataString = string(abi.encodePacked(metadataString, ","));
            metadataString = string(
                abi.encodePacked(
                    metadataString,
                    '{"trait_type":"Placement","value":"',
                    MaticMikeLibrary.toString(placed),
                    '%"',
                    '}'
                )
            );
        }

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
        string memory svgString;
        string memory _hash;

        _hash = IECL(eclAddress)._tokenIdToHash(_tokenId);

        svgString = bodyMap[MaticMikeLibrary.parseInt(MaticMikeLibrary.substring(_hash, 8, 9))];

        for (uint8 i = 0; i < 9; i++) {
            uint8 thisTraitIndex = MaticMikeLibrary.parseInt(
                MaticMikeLibrary.substring(_hash, i, i + 1)
            );

            if(traitTypes[i][thisTraitIndex].pixelCount > 0){
                svgString = string(
                    abi.encodePacked(
                        svgString,
                        traitTypes[i][thisTraitIndex].pixels
                    )
                );
            }
        }

        // external contract call for boss loot and graphics
        if(xxlAddress != nullAddress){
            IMikeExtended.Traits[] memory XxlTraits = IMikeExtended(xxlAddress).getAllPlayerLoot(_tokenId);

            for(uint256 i=0; i < XxlTraits.length; i++){
                if(XxlTraits[i].valid && XxlTraits[i].pixelCount > 0){
                    svgString = string(
                        abi.encodePacked(
                            svgString,
                            XxlTraits[i].pixels
                        )
                    );
                }
            }
        }

        svgString = string(
            abi.encodePacked(
                '<svg id="ecl-svg" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMinYMin meet" viewBox="0 0 24 24"> ',
                svgString,
                '<style>#ecl-svg{shape-rendering:crispedges}rect{width:1px;height:1px}.c00{fill:#000}.c01{fill:#474747}.c02{fill:#d6d6d6}.c03{fill:#b2b2b2}.c04{fill:#582a07}.c05{fill:#301501}.c06{fill:#9b643a}.c07{fill:#70401b}.c08{fill:#130800}.c09{fill:#d79968}.c10{fill:#b77f53}.c11{fill:#e5b893}.c12{fill:#f5cfb1}.c13{fill:#eab0b0}.c14{fill:#818eef}.c15{fill:#5d6acb}.c16{fill:#0a23e2}.c17{fill:#e981ef}.c18{fill:#b542bc}.c19{fill:#e20ada}.c20{fill:#fce311}.c21{fill:#f1f1f1}.c22{fill:red}.c23{fill:#ff6868}.c24{fill:#1be947}.c25{fill:#d34917}.c26{fill:#fff}.c27{fill:#b0e8ef}.c28{fill:#c5e3e7}.c29{fill:#f88fff}.c30{fill:orange}.c31{fill:#ff0}.c32{fill:green}.c33{fill:#00f}.c34{fill:indigo}.c35{fill:violet}.c36{fill:#e6ebb0}.c37{fill:#2c2100}.c38{fill:#364b6d}.c39{fill:#1c1c1c}.c40{fill:#fa7c73}.c41{fill:#f10}.c42{fill:#8fd1ff}.c43{fill:#d4edff}.c44{fill:#81deef}.c45{fill:#6fccdd}.c46{fill:#ff6400}.c47{fill:#ff9b00}.c48{fill:#ff6500}.c49{fill:#fff400}.c50{fill:#ffe000}.c51{fill:#b9ff00}.c52{fill:#cbff00}.c53{fill:#3cff00}.c54{fill:#4bff00}.c55{fill:#00ff15}.c56{fill:#00ff0d}.c57{fill:#00ff8a}.c58{fill:#00ff7f}.c59{fill:#00fff7}.c60{fill:#00fff2}.c61{fill:#00acff}.c62{fill:#00b4ff}.c63{fill:#002eff}.c64{fill:#0034ff}.c65{fill:#a000ff}.c66{fill:#9a00ff}.c67{fill:#ff00f0}.c68{fill:#ff00f4}.c69{fill:#ff006d}.c70{fill:#ff0074}.c71{fill:#9700f0}.c72{fill:#dca1ff}.c73{fill:#cbb4f1}.c74{fill:#7d00c7}.c75{fill:#56768e}.c76{fill:#dc3c39}.c77{fill:#fe4341}.c78{fill:#e00000}.c79{fill:#ed0000}.c80{fill:#666}.c81{fill:#6e6e6e}.c82{fill:#7c7b7b}.c83{fill:#fef5ff}</style></svg>'
            )
        );

        return MaticMikeLibrary.encode(bytes(svgString));
    }

    /*********************************
    *   Trait insertion functions
    **********************************/

    /**
     * @dev Clears the traits.
     */
    function clearTraits() public onlyOwner {
        for (uint256 i = 0; i < 9; i++) {
            delete traitTypes[i];
        }
    }

    /**
     * @dev Add a svg to trait for large svgs
     * @param thisTrait is the id of the trait
     * @param thisTraitIndex is the index of the trait we're adding
     * @param svg is the long svg string
     */
    function populateSVG(uint8 thisTrait, uint256 thisTraitIndex, string memory svg) public onlyOwner
    {
        traitTypes[thisTrait][thisTraitIndex].pixels = svg;
    }

    /**
     * @dev Add a trait type
     * @param _traitTypeIndex The trait type index
     * @param traits Array of traits to add
     */
    function addTraitType(uint256 _traitTypeIndex, Trait[] memory traits)
        public
        onlyOwner
    {
        for (uint256 i = 0; i < traits.length; i++) {
            traitTypes[_traitTypeIndex].push(
                Trait(
                    traits[i].traitName,
                    traits[i].traitType,
                    traits[i].pixels,
                    traits[i].pixelCount,
                    traits[i].powerLevel
                )
            );
        }

        return;
    }

    function setECLAddress(address _address) public onlyOwner{
        eclAddress = _address;
    }
    
    function setMmAddress(address _address) public onlyOwner{
        mmAddress = _address;
    }
    
    function setXxlAddress(address _address) public onlyOwner{
        xxlAddress = _address;
    }

    function setDanceOffAddress(address _address) public onlyOwner{
        danceoffAddress = _address;
    }

    /**
     * @dev Modifier to only allow owner to call functions
     */
    modifier onlyOwner() {
        require(_owner == msg.sender);
        _;
    }
}