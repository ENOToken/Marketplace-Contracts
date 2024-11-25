// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title NFTDataStructures
/// @notice Contract that defines data structures for NFT creation
/// @dev This contract is meant to be imported by other contracts
contract NFTDataStructures {
    /// @notice Structure containing all parameters needed to create an NFT collection
    /// @param name Name of the NFT collection
    /// @param symbol Symbol of the NFT collection
    /// @param commissionWallet Address of the commission wallet
    /// @param ownerWallet Address of the owner wallet
    /// @param saleStartTime Timestamp when the sale starts
    /// @param maxMintsPerWallet Maximum number of mints allowed per wallet
    /// @param maxSupply Maximum supply of tokens
    /// @param NFTPriceInETH Price of each NFT in ETH
    /// @param sameMetadataForAll Whether all tokens share the same metadata
    /// @param commission Commission percentage for each sale
    /// @param metadataURI URI for the NFT metadata
    struct NFTCreateParams {
        string name;
        string symbol;
        address commissionWallet;
        address ownerWallet;
        uint256 saleStartTime;
        uint256 maxMintsPerWallet;
        uint256 maxSupply;
        uint256 NFTPriceInETH;
        bool sameMetadataForAll;
        uint256 commission;
        string metadataURI;
    }

}