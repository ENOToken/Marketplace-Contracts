// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts@4.8.0/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/access/OwnableUpgradeable.sol";
import "./NFTENOOnlyETH.sol";
import "./NFTDataStructures.sol";

// Este es tu factory actual pero con los cambios para hacerlo actualizable
contract CustomNFTFactoryV1 is Initializable, OwnableUpgradeable {
    mapping(uint256 => address) public createdNFTs;
    uint256 public totalNFTs;

    event NFTCreated(
        address indexed creator, 
        address indexed nftAddress, 
        uint256 indexed index, 
        string name, 
        string symbol,
        string metadataURI
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
    }

    function _createNFTContract(NFTDataStructures.NFTCreateParams memory params) internal returns (address) {
        return address(new CustomNFT(
            params.name,
            params.symbol,
            params.commissionWallet,
            params.ownerWallet,
            params.saleStartTime,
            params.maxMintsPerWallet,
            params.maxSupply,
            params.NFTPriceInETH,
            params.sameMetadataForAll,
            params.commission,
            params.metadataURI
        ));
    }

    function createNFT(NFTDataStructures.NFTCreateParams memory params) external returns (address) {
        address nftAddress = _createNFTContract(params);
        
        createdNFTs[totalNFTs] = nftAddress;
        
        emit NFTCreated(
            msg.sender, 
            nftAddress, 
            totalNFTs, 
            params.name, 
            params.symbol,
            params.metadataURI
        );
        
        totalNFTs++;
        return nftAddress;
    }

    function getNumberOfCreatedNFTs() external view returns (uint256) {
        return totalNFTs;
    }

    function getCreatedNFTsPaginated(uint256 offset, uint256 limit) external view returns (address[] memory) {
        require(offset < totalNFTs, "Offset out of bounds");
        
        uint256 endIndex = offset + limit;
        if (endIndex > totalNFTs) {
            endIndex = totalNFTs;
        }
        
        uint256 length = endIndex - offset;
        address[] memory result = new address[](length);
        
        for (uint256 i = 0; i < length; i++) {
            result[i] = createdNFTs[offset + i];
        }
        
        return result;
    }
}