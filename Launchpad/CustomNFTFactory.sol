// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./CustomNFT.sol";
import "./NFTDataStructures.sol";
import "./Constants.sol";

/// @title Custom NFT Factory with improved features and security
/// @notice Factory contract for deploying CustomNFT contracts with extensive configuration options
contract CustomNFTFactory is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // Events
    event NFTCreated(
        address indexed creator,
        address indexed nftAddress,
        string name,
        string symbol,
        string metadataURI,
        bool metadataMutable,
        uint256 secondaryRoyaltyFee,
        uint256 maxSupply,
        uint256 NFTPriceInETH,
        address[] royaltyWallets, // Nuevo parámetro
        uint256[] logicalPercentages
    );
    event ContractPaused(address indexed operator);
    event ContractUnpaused(address indexed operator);

    // Custom errors
    error InvalidPlatformWallet();
    error InvalidRoyaltyWallets();
    error InvalidPercentages();
    error InvalidSecondaryRoyalty();
    error InvalidMaxSupply();
    error InvalidPrice();
    error InvalidMaxMints();
    error WalletsPercentagesMismatch();
    error TooManyWallets();
    error DuplicateRoyaltyWallet();
    error InvalidName();
    error InvalidSymbol();
    error InvalidMetadataURI();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable_init();
        __Pausable_init();
        __ReentrancyGuard_init();
    }

    /// @notice Creates a new NFT contract with the given parameters
    /// @param params Struct containing all necessary parameters for NFT creation
    function createNFT(
        NFTDataStructures.NFTCreateParams memory params
    ) external whenNotPaused nonReentrant returns (address) {
        // Validate parameters
        if (bytes(params.name).length == 0) revert InvalidName();
        if (bytes(params.symbol).length == 0) revert InvalidSymbol();
        if (bytes(params.metadataURI).length == 0) revert InvalidMetadataURI();
        if (params.platformWallet == address(0)) revert InvalidPlatformWallet();
        if (params.maxSupply == 0) revert InvalidMaxSupply();
        if (
            params.secondaryRoyaltyFee < NFTConstants.MIN_SECONDARY_ROYALTY ||
            params.secondaryRoyaltyFee > NFTConstants.MAX_SECONDARY_ROYALTY
        ) revert InvalidSecondaryRoyalty();
        if (params.royaltyWallets.length != params.logicalPercentages.length)
            revert WalletsPercentagesMismatch();
        if (params.royaltyWallets.length > NFTConstants.MAX_WALLETS)
            revert TooManyWallets();

        // Validate royalty wallets and percentages
        uint256 totalPercentage;
        for (uint256 i = 0; i < params.royaltyWallets.length; i++) {
            if (params.royaltyWallets[i] == address(0))
                revert InvalidRoyaltyWallets();
            totalPercentage += params.logicalPercentages[i];
        }
        for (uint256 i = 0; i < params.royaltyWallets.length; i++) {
            for (uint256 j = i + 1; j < params.royaltyWallets.length; j++) {
                if (params.royaltyWallets[i] == params.royaltyWallets[j])
                    revert DuplicateRoyaltyWallet();
            }
        }
        if (totalPercentage != 10000) revert InvalidPercentages();

        params.initialOwner = msg.sender;

        // Create NFT contract
        address nftAddress = address(new CustomNFT(params));

        emit NFTCreated(
            msg.sender,
            nftAddress,
            params.name,
            params.symbol,
            params.metadataURI,
            params.metadataMutable,
            params.secondaryRoyaltyFee,
            params.maxSupply,
            params.NFTPriceInETH,
            params.royaltyWallets,
            params.logicalPercentages
        );

        return nftAddress;
    }

    function pause() external onlyOwner {
        _pause();
        emit ContractPaused(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }
}
