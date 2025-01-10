// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable@4.8.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/security/ReentrancyGuardUpgradeable.sol";
import "./CustomNFT.sol";
import "./NFTDataStructures.sol";

/// @title Custom NFT Factory with improved features and security
/// @notice Factory contract for deploying CustomNFT contracts with extensive configuration options
contract CustomNFTFactory is
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // State variables
    mapping(uint256 => address) public createdNFTs;
    mapping(address => bool) public isNFTCreated;
    uint256 public totalNFTs;

    // Constants
    uint256 public constant MIN_SECONDARY_ROYALTY = 200; // 2%
    uint256 public constant MAX_SECONDARY_ROYALTY = 1000; // 10%
    uint256 public constant MAX_WALLETS = 10;

    // Events
    event NFTCreated(
        address indexed creator,
        address indexed nftAddress,
        uint256 indexed index,
        string name,
        string symbol,
        string metadataURI,
        bool metadataMutable,
        uint256 secondaryRoyaltyFee
    );

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
        if (params.platformWallet == address(0)) revert InvalidPlatformWallet();
        if (params.maxSupply == 0) revert InvalidMaxSupply();
        if (params.NFTPriceInETH == 0) revert InvalidPrice();
        if (
            params.secondaryRoyaltyFee < MIN_SECONDARY_ROYALTY ||
            params.secondaryRoyaltyFee > MAX_SECONDARY_ROYALTY
        ) revert InvalidSecondaryRoyalty();
        if (params.royaltyWallets.length != params.logicalPercentages.length)
            revert WalletsPercentagesMismatch();
        if (params.royaltyWallets.length > MAX_WALLETS) revert TooManyWallets();

        // Validate royalty wallets and percentages
        uint256 totalPercentage;
        for (uint256 i = 0; i < params.royaltyWallets.length; i++) {
            if (params.royaltyWallets[i] == address(0))
                revert InvalidRoyaltyWallets();
            totalPercentage += params.logicalPercentages[i];
        }
        if (totalPercentage != 10000) revert InvalidPercentages();

        params.initialOwner = msg.sender;

        // Create NFT contract
        address nftAddress = address(new CustomNFT(params));

        // Update state
        createdNFTs[totalNFTs] = nftAddress;
        isNFTCreated[nftAddress] = true;

        emit NFTCreated(
            msg.sender,
            nftAddress,
            totalNFTs,
            params.name,
            params.symbol,
            params.metadataURI,
            params.metadataMutable,
            params.secondaryRoyaltyFee
        );

        totalNFTs++;
        return nftAddress;
    }

    /// @notice Returns the total number of NFT contracts created
    function getNumberOfCreatedNFTs() external view returns (uint256) {
        return totalNFTs;
    }

    /// @notice Returns a paginated list of created NFT contracts
    /// @param offset Starting index
    /// @param limit Maximum number of addresses to return
    function getCreatedNFTsPaginated(
        uint256 offset,
        uint256 limit
    ) external view returns (address[] memory) {
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

    /// @notice Checks if an address is a valid NFT contract created by this factory
    /// @param nftAddress Address to check
    function isValidNFTContract(
        address nftAddress
    ) external view returns (bool) {
        return isNFTCreated[nftAddress];
    }

    /// @notice Pauses the contract
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyOwner {
        _unpause();
    }
}
