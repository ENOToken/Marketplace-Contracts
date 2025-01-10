// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title NFT Data Structures
 * @notice Defines all data structures used by the NFT contracts
 */
library NFTDataStructures {
    struct NFTCreateParams {
        string name;
        string symbol;
        address platformWallet;
        address initialOwner;
        address[] royaltyWallets;
        uint256[] logicalPercentages;
        uint256 saleStartTime;
        uint256 maxSupply;
        uint256 maxMintsPerWallet;
        uint256 NFTPriceInETH;
        bool sameMetadataForAll;
        bool metadataMutable;
        uint256 secondaryRoyaltyFee;
        string metadataURI;
    }

    struct RoyaltyConfig {
        address[] wallets;
        uint256[] percentages;
        uint256 secondaryRoyaltyFee;
    }

    struct TokenConfig {
        bool sameMetadataForAll;
        bool metadataMutable;
        string baseURI;
        string commonMetadataURI;
    }

    struct SaleConfig {
        uint256 saleStartTime;
        uint256 maxSupply;
        uint256 maxMintsPerWallet;
        uint256 NFTPriceInETH;
    }
}
