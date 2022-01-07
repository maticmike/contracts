// contracts/DanceAnalytics.sol
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interface/IDanceOffLegacy.sol";
import "./interface/IDanceOff.sol";

contract DanceAnalytics is Ownable{

    address mmDataAddress;
    address eclDataAddress;

    address hghroyale;
    address wethroyale;
    address eventsroyale;

    address mmAddress;
    address eclAddress;
    address danceoffLegacy;

    address[] danceoffAddresses;

    struct Entries{
        address _contract;
        uint256[] entries;
    }

    struct WinnerGroup{
        address _contract;
        IDanceOff.Winner[] _winners;
    }

    constructor() {}

    /**
    * @dev legacy call for data contracts to pull info for metadata
    * @param _tokenId is the token info being pulled and compiled
    */
    function getRumblesEntered(uint256 _tokenId) public view returns (uint256[] memory){
        require(msg.sender == mmDataAddress || eclDataAddress == msg.sender, "Not part of the Matic Mike Family of Contracts");

        uint256 arrLength = 0;
        address caller;

        if(msg.sender == mmDataAddress){
            caller = mmAddress;

            arrLength += IDanceOffLegacy(danceoffLegacy).getRumblesEntered(_tokenId).length;
        }
        else if(msg.sender == eclDataAddress){
            caller = eclAddress;
        }
        for(uint8 i=0; i<danceoffAddresses.length; i++){
            arrLength += IDanceOff(danceoffAddresses[i]).getRumblesEntered(_tokenId, caller).length;
        }

        uint256[] memory dummyArr = new uint256[](arrLength);
        return dummyArr;
    }

    /**
    * @dev New call for web3 to pull info for metadata
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getRumblesEnteredNew(uint256 _tokenId, address _caller) public view returns (uint256[] memory){
        Entries[] memory rumbles = new Entries[](danceoffAddresses.length+1);
        uint256 index = 0;
        uint256 returnSize = 0;

        if(_caller == mmAddress){
            uint256[] memory tempArr = IDanceOffLegacy(danceoffLegacy).getRumblesEntered(_tokenId);
            rumbles[index] = Entries(
                danceoffLegacy,
                tempArr
            );

            returnSize += tempArr.length;
            index++;
        }

        for(uint8 i=0; i<danceoffAddresses.length; i++){
            uint256[] memory tempArr = IDanceOff(danceoffAddresses[i]).getRumblesEntered(_tokenId, _caller);
            rumbles[index] = Entries(
                danceoffAddresses[i],
                tempArr
            );
            
            returnSize += tempArr.length;
            index++;
        }

        uint256[] memory rumblesRaw = new uint256[](returnSize);

        uint k=0;
        for(uint8 i=0; i<index; i++){
            for(uint256 j=0; j<rumbles[i].entries.length; j++){
                rumblesRaw[k] = rumbles[i].entries[j];
                k++;
            }
        }

        return rumblesRaw;
    }

    /**
    * @dev legacy call for data contracts to pull info for metadata
    * @param _tokenId is the token info being pulled and compiled
    */
    function getPlacementsByToken(uint256 _tokenId) public view returns(IDanceOffLegacy.Winner[] memory){
        require(msg.sender == mmDataAddress || eclDataAddress == msg.sender, "Not part of the Matic Mike Family of Contracts");

        IDanceOffLegacy.Winner[] memory WinnersLegacy;
        uint256 returnSize = 0;

        address caller;

        if(msg.sender == mmDataAddress){
            caller = mmAddress;
            WinnersLegacy = IDanceOffLegacy(danceoffLegacy).getPlacementsByToken(_tokenId);
            returnSize += WinnersLegacy.length;
        }
        else if(msg.sender == eclDataAddress){
            caller = eclAddress;
        }

        for(uint8 i=0; i<danceoffAddresses.length; i++){
            IDanceOff.Winner[] memory WinnersNew = IDanceOff(danceoffAddresses[i]).getPlacementsByToken(_tokenId, caller);
            returnSize += WinnersNew.length;
        }

        IDanceOffLegacy.Winner[] memory WinnerReturn = new IDanceOffLegacy.Winner[](returnSize);
        
        // just return an empty array with a set length for legacy
        return WinnerReturn;
    }

    /**
    * @dev Get all wins grouped by danceoff contract address for easy front-end display
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getPlacementsGrouped(uint256 _tokenId, address _caller) public view returns(WinnerGroup[] memory){
        IDanceOffLegacy.Winner[] memory WinnersLegacy;
        WinnerGroup[] memory WinnerContainer = new WinnerGroup[](danceoffAddresses.length+1);

        uint256 index = 0;

        address caller;

        if(_caller == mmAddress){
            caller = mmAddress;
            WinnersLegacy = IDanceOffLegacy(danceoffLegacy).getPlacementsByToken(_tokenId);
            
            IDanceOff.Winner[] memory WinnerReturn = new IDanceOff.Winner[](WinnersLegacy.length);
            if(WinnersLegacy.length > 0){
                for(uint256 i=0; i<WinnersLegacy.length; i++){
                    WinnerReturn[i] = IDanceOff.Winner(
                        WinnersLegacy[i].tokenId,
                        mmAddress,
                        WinnersLegacy[i].placement,
                        WinnersLegacy[i].rumbleId,
                        WinnersLegacy[i].payout,
                        WinnersLegacy[i].holder
                    );
                }
            }

            WinnerContainer[index] = WinnerGroup(
                danceoffLegacy,
                WinnerReturn
            );
            
            index++;
        }
        else if(_caller == eclAddress){
            caller = eclAddress;
        }

        for(uint8 i=0; i<danceoffAddresses.length; i++){
            IDanceOff.Winner[] memory WinnersNew = IDanceOff(danceoffAddresses[i]).getPlacementsByToken(_tokenId, caller);
            WinnerContainer[index] = WinnerGroup(
                danceoffAddresses[i],
                WinnersNew
            );
            
            index++;
        }

        return WinnerContainer;
    }

    /**
    * @dev call for data contracts to pull info for metadata
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getPlacementsNew(uint256 _tokenId, address _caller) public view returns(IDanceOff.Winner[] memory){
        IDanceOffLegacy.Winner[] memory WinnersLegacy;
        WinnerGroup[] memory WinnerContainer = new WinnerGroup[](danceoffAddresses.length);

        uint256 index = 0;
        uint256 returnSize = 0;

        address caller;

        if(_caller == mmAddress){
            caller = mmAddress;
            WinnersLegacy = IDanceOffLegacy(danceoffLegacy).getPlacementsByToken(_tokenId);
            returnSize += WinnersLegacy.length;
        }
        else if(_caller == eclAddress){
            caller = eclAddress;
        }

        for(uint8 i=0; i<danceoffAddresses.length; i++){
            IDanceOff.Winner[] memory WinnersNew = IDanceOff(danceoffAddresses[i]).getPlacementsByToken(_tokenId, caller);
            WinnerContainer[i] = WinnerGroup(
                danceoffAddresses[i],
                WinnersNew
            );
            
            returnSize += WinnersNew.length;
        }

        IDanceOff.Winner[] memory WinnerReturn = new IDanceOff.Winner[](returnSize);
        if(WinnersLegacy.length > 0){
            for(uint256 i=0; i<WinnersLegacy.length; i++){
                WinnerReturn[index] = IDanceOff.Winner(
                    WinnersLegacy[i].tokenId,
                    mmAddress,
                    WinnersLegacy[i].placement,
                    WinnersLegacy[i].rumbleId,
                    WinnersLegacy[i].payout,
                    WinnersLegacy[i].holder
                );
                index++;
            }
        }

        for(uint256 i=0; i<WinnerContainer.length; i++){
            for(uint256 j=0; j<WinnerContainer[i]._winners.length; j++){
                WinnerReturn[index] = WinnerContainer[i]._winners[j];
                index++;
            }
        }

        return WinnerReturn;
    }

    /**
    * @dev get dynamic contract placements
    * @param _contract contract of the royale
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getPlacementsByContract(address _contract, uint256 _tokenId, address _caller) public view returns(IDanceOff.Winner[] memory){
        if(_contract == hghroyale){
            IDanceOffLegacy.Winner[] memory WinnersLegacy;

            uint256 index = 0;
            uint256 returnSize = 0;

            address caller;

            if(_caller == mmAddress){
                caller = mmAddress;
                WinnersLegacy = IDanceOffLegacy(danceoffLegacy).getPlacementsByToken(_tokenId);
                returnSize += WinnersLegacy.length;
            }
            else if(_caller == eclAddress){
                caller = eclAddress;
            }

            IDanceOff.Winner[] memory WinnersNew = IDanceOff(hghroyale).getPlacementsByToken(_tokenId, caller);
            
            returnSize += WinnersNew.length;

            IDanceOff.Winner[] memory WinnerReturn = new IDanceOff.Winner[](returnSize);
            if(WinnersLegacy.length > 0){
                for(uint256 i=0; i<WinnersLegacy.length; i++){
                    WinnerReturn[index] = IDanceOff.Winner(
                        WinnersLegacy[i].tokenId,
                        mmAddress,
                        WinnersLegacy[i].placement,
                        WinnersLegacy[i].rumbleId,
                        WinnersLegacy[i].payout,
                        WinnersLegacy[i].holder
                    );
                    index++;
                }
            }

            for(uint256 i=0; i<WinnersNew.length; i++){
                WinnerReturn[index] = WinnersNew[i];
                index++;
            }

            return WinnerReturn;
        }
        else{
            IDanceOff.Winner[] memory WinnersNew = IDanceOff(wethroyale).getPlacementsByToken(_tokenId, _caller);

            return WinnersNew;
        }
    }

    /**
    * @dev get HGH placements
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getPlacementsHGH(uint256 _tokenId, address _caller) public view returns(IDanceOff.Winner[] memory){
        IDanceOffLegacy.Winner[] memory WinnersLegacy;

        uint256 index = 0;
        uint256 returnSize = 0;

        address caller;

        if(_caller == mmAddress){
            caller = mmAddress;
            WinnersLegacy = IDanceOffLegacy(danceoffLegacy).getPlacementsByToken(_tokenId);
            returnSize += WinnersLegacy.length;
        }
        else if(_caller == eclAddress){
            caller = eclAddress;
        }

        IDanceOff.Winner[] memory WinnersNew = IDanceOff(hghroyale).getPlacementsByToken(_tokenId, caller);
        
        returnSize += WinnersNew.length;

        IDanceOff.Winner[] memory WinnerReturn = new IDanceOff.Winner[](returnSize);
        if(WinnersLegacy.length > 0){
            for(uint256 i=0; i<WinnersLegacy.length; i++){
                WinnerReturn[index] = IDanceOff.Winner(
                    WinnersLegacy[i].tokenId,
                    mmAddress,
                    WinnersLegacy[i].placement,
                    WinnersLegacy[i].rumbleId,
                    WinnersLegacy[i].payout,
                    WinnersLegacy[i].holder
                );
                index++;
            }
        }

        for(uint256 i=0; i<WinnersNew.length; i++){
            WinnerReturn[index] = WinnersNew[i];
            index++;
        }

        return WinnerReturn;
    }

    /**
    * @dev get WETH placements
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getPlacementsWETH(uint256 _tokenId, address _caller) public view returns(IDanceOff.Winner[] memory){
        IDanceOff.Winner[] memory WinnersNew = IDanceOff(wethroyale).getPlacementsByToken(_tokenId, _caller);

        return WinnersNew;
    }

    /**
    * @dev get Events Placements
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getPlacementsEvents(uint256 _tokenId, address _caller) public view returns(IDanceOff.Winner[] memory){
        IDanceOff.Winner[] memory WinnersNew = IDanceOff(eventsroyale).getPlacementsByToken(_tokenId, _caller);

        return WinnersNew;
    }

    /**
    * @dev Get Rumble Count For Any Royales token
    * @param _contract is the contract address of the royale contract
    * @param _tokenId is the token info being pulled and compiled
    * @param _caller is the token contract address
    */
    function getRumbleCountByContract(address _contract, uint256 _tokenId, address _caller) public view returns (uint256){
        uint256 entryCount = 0;

        if(_contract == hghroyale){
            if(_caller == mmAddress){
                entryCount += IDanceOffLegacy(danceoffLegacy).getRumblesEntered(_tokenId).length;
            }
        }
        
        entryCount += IDanceOff(_contract).getRumblesEntered(_tokenId, _caller).length;

        return entryCount;
    }

    /**
    * @dev Set the data addresses
    * @param _mmData matic mike data address
    * @param _eclData ecl data address
    */
    function setDataAddress(address _mmData, address _eclData) public onlyOwner{
        mmDataAddress = _mmData;
        eclDataAddress = _eclData;
    }

    /**
    * @dev Set the NFT addresses as well as legacy danceoff
    * @param _mmAddress matic mike address
    * @param _eclAddress ecl address
    * @param _danceoffLegacy danceoff legacy address
    */
    function setNFTAddress(address _mmAddress, address _eclAddress, address _danceoffLegacy) public onlyOwner{
        mmAddress = _mmAddress;
        eclAddress = _eclAddress;
        danceoffLegacy = _danceoffLegacy;
    }

    /**
    * @dev Set the hgh royale contract
    * @param _address address of contract
    */
    function setHghRoyale(address _address) public onlyOwner{
        hghroyale = _address;
    }

    /**
    * @dev Set the weth royale contract
    * @param _address address of contract
    */
    function setWethRoyale(address _address) public onlyOwner{
        wethroyale = _address;
    }

    /**
    * @dev Set the events royale contract
    * @param _address address of contract
    */
    function setEventsRoyale(address _address) public onlyOwner{
        eventsroyale = _address;
    }

    /**
    * @dev Set all the new danceoff addresses
    * @param _addresses all the dance off addresses
    */
    function setDanceoffAddresses(address[] memory _addresses) public onlyOwner{
        danceoffAddresses = _addresses;
    }
}