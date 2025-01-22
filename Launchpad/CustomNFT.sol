// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "./NFTDataStructures.sol";
import "./Constants.sol";

contract CustomNFT is
    ERC721Enumerable,
    IERC2981,
    Ownable,
    ReentrancyGuard,
    Pausable
{
    using Strings for uint256;
    using NFTDataStructures for *;

    // Configurations
    NFTDataStructures.RoyaltyConfig private royaltyConfig;
    NFTDataStructures.TokenConfig private tokenConfig;
    NFTDataStructures.SaleConfig public saleConfig;
    address public immutable platformWallet;

    // Minting state
    uint256 private _tokenIdCounter = 1;
    mapping(address => uint256) private _mintedCount;
    bool public emergencyMode;

    // Events
    event PrimarySale(
        address indexed buyer,
        uint256 tokenId,
        uint256 price,
        uint256 timestamp
    );
    event RoyaltyPaid(
        address indexed recipient,
        uint256 amount,
        string royaltyType,
        uint256 timestamp
    );
    event RoyaltiesConfigured(
        address[] wallets,
        uint256[] logicalPercentages,
        uint256 timestamp
    );
    event MetadataUpdated(
        string newBaseURI,
        string newCommonMetadataURI,
        uint256 timestamp
    );
    event EmergencyModeChanged(bool enabled, uint256 timestamp);
    event SecondaryRoyaltyDistributed(uint256 totalAmount, uint256 timestamp);

    // Custom errors
    error InvalidPlatformWallet();
    error InvalidRoyaltyWallets();
    error InvalidPercentages();
    error InvalidSecondaryRoyalty();
    error WalletsPercentagesMismatch();
    error TooManyWallets();
    error SaleNotStarted();
    error MaxMintsExceeded();
    error MaxSupplyReached();
    error IncorrectPayment();
    error EmergencyModeActive();
    error ImmutableMetadata();
    error TransferFailed();
    error DuplicateRoyaltyWallet();

    constructor(
        NFTDataStructures.NFTCreateParams memory params
    ) ERC721(params.name, params.symbol) {
        if (params.platformWallet == address(0)) revert InvalidPlatformWallet();
        if (params.royaltyWallets.length != params.logicalPercentages.length)
            revert WalletsPercentagesMismatch();
        if (params.royaltyWallets.length > NFTConstants.MAX_WALLETS)
            revert TooManyWallets();
        if (
            params.secondaryRoyaltyFee < NFTConstants.MIN_SECONDARY_ROYALTY ||
            params.secondaryRoyaltyFee > NFTConstants.MAX_SECONDARY_ROYALTY
        ) revert InvalidSecondaryRoyalty();
        for (uint256 i = 0; i < params.royaltyWallets.length; i++) {
            for (uint256 j = i + 1; j < params.royaltyWallets.length; j++) {
                if (params.royaltyWallets[i] == params.royaltyWallets[j])
                    revert DuplicateRoyaltyWallet();
            }
        }
        uint256 totalLogicalPercentage;
        for (uint256 i = 0; i < params.logicalPercentages.length; i++) {
            if (params.royaltyWallets[i] == address(0))
                revert InvalidRoyaltyWallets();
            totalLogicalPercentage += params.logicalPercentages[i];
        }
        if (totalLogicalPercentage != 10000) revert InvalidPercentages();

        platformWallet = params.platformWallet;

        royaltyConfig.wallets = params.royaltyWallets;
        royaltyConfig.percentages = params.logicalPercentages;
        royaltyConfig.secondaryRoyaltyFee = params.secondaryRoyaltyFee;

        tokenConfig.sameMetadataForAll = params.sameMetadataForAll;
        tokenConfig.metadataMutable = params.metadataMutable;
        if (params.sameMetadataForAll) {
            tokenConfig.commonMetadataURI = params.metadataURI;
        } else {
            tokenConfig.baseURI = params.metadataURI;
        }

        if (params.initialOwner != address(0)) {
            _transferOwnership(params.initialOwner);
        }

        saleConfig.saleStartTime = params.saleStartTime;
        saleConfig.maxSupply = params.maxSupply;
        saleConfig.NFTPriceInETH = params.NFTPriceInETH;

        emit RoyaltiesConfigured(
            params.royaltyWallets,
            params.logicalPercentages,
            block.timestamp
        );
    }

    function buyNFTWithETH() public payable nonReentrant whenNotPaused {
        if (emergencyMode) revert EmergencyModeActive();
        if (block.timestamp < saleConfig.saleStartTime) revert SaleNotStarted();
        if (msg.value != saleConfig.NFTPriceInETH) revert IncorrectPayment();
        if (_mintedCount[msg.sender] >= saleConfig.maxMintsPerWallet)
            revert MaxMintsExceeded();
        if (_tokenIdCounter > saleConfig.maxSupply) revert MaxSupplyReached();

        uint256 tokenId = _tokenIdCounter++;
        _mint(msg.sender, tokenId);
        _mintedCount[msg.sender]++;

        _processPrimarySale();

        emit PrimarySale(msg.sender, tokenId, msg.value, block.timestamp);
    }

    function _processPrimarySale() private {
        uint256 platformAmount = (msg.value * NFTConstants.PLATFORM_FEE) /
            10000;
        uint256 remainingAmount = msg.value - platformAmount;

        (bool success, ) = platformWallet.call{value: platformAmount}("");
        if (!success) revert TransferFailed();
        emit RoyaltyPaid(
            platformWallet,
            platformAmount,
            "platform",
            block.timestamp
        );

        for (uint256 i = 0; i < royaltyConfig.wallets.length; i++) {
            uint256 amount = (remainingAmount * royaltyConfig.percentages[i]) /
                10000;
            (success, ) = royaltyConfig.wallets[i].call{value: amount}("");
            if (!success) revert TransferFailed();
            emit RoyaltyPaid(
                royaltyConfig.wallets[i],
                amount,
                "primary",
                block.timestamp
            );
        }
    }

    function distributeRoyalties(
        uint256 amount
    ) external payable nonReentrant returns (bool) {
        require(msg.value == amount, "Incorrect royalty amount");
        require(amount > 0, "Amount must be greater than 0"); // Añadir esta validación

        uint256 remainingAmount = amount; // Para verificar que se distribuye todo
        bool success;

        for (uint256 i = 0; i < royaltyConfig.wallets.length; i++) {
            uint256 walletAmount = (amount * royaltyConfig.percentages[i]) /
                10000;
            remainingAmount -= walletAmount;

            (success, ) = royaltyConfig.wallets[i].call{value: walletAmount}(
                ""
            );
            if (!success) revert TransferFailed();

            emit RoyaltyPaid(
                royaltyConfig.wallets[i],
                walletAmount,
                "secondary",
                block.timestamp
            );
        }

        require(remainingAmount == 0, "Distribution error"); // Verificar distribución completa
        emit SecondaryRoyaltyDistributed(amount, block.timestamp);
        return true;
    }

    function updateRoyalties(
        address[] memory wallets,
        uint256[] memory percentages
    ) public nonReentrant onlyOwner {
        if (wallets.length != percentages.length)
            revert WalletsPercentagesMismatch();
        if (wallets.length > NFTConstants.MAX_WALLETS) revert TooManyWallets();
        // Añadir validación de wallets duplicados
        for (uint256 i = 0; i < wallets.length; i++) {
            for (uint256 j = i + 1; j < wallets.length; j++) {
                if (wallets[i] == wallets[j]) revert DuplicateRoyaltyWallet();
            }
        }
        uint256 totalLogicalPercentage;
        for (uint256 i = 0; i < percentages.length; i++) {
            if (wallets[i] == address(0)) revert InvalidRoyaltyWallets();
            totalLogicalPercentage += percentages[i];
        }
        if (totalLogicalPercentage != 10000) revert InvalidPercentages();

        royaltyConfig.wallets = wallets;
        royaltyConfig.percentages = percentages;

        emit RoyaltiesConfigured(wallets, percentages, block.timestamp);
    }

    function updateMetadata(
        string memory newBaseURI,
        string memory newCommonMetadataURI
    ) public onlyOwner {
        if (!tokenConfig.metadataMutable) revert ImmutableMetadata();

        tokenConfig.baseURI = newBaseURI;
        tokenConfig.commonMetadataURI = newCommonMetadataURI;

        emit MetadataUpdated(newBaseURI, newCommonMetadataURI, block.timestamp);
    }

    function toggleEmergencyMode() external onlyOwner {
        emergencyMode = !emergencyMode;
        emit EmergencyModeChanged(emergencyMode, block.timestamp);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function royaltyInfo(
        uint256,
        uint256 salePrice
    ) external view override returns (address, uint256) {
        return (
            address(this),
            (salePrice * royaltyConfig.secondaryRoyaltyFee) / 10000
        );
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        if (tokenConfig.sameMetadataForAll) {
            require(
                bytes(tokenConfig.commonMetadataURI).length > 0,
                "Empty URI"
            );
            return tokenConfig.commonMetadataURI;
        } else {
            require(bytes(tokenConfig.baseURI).length > 0, "Empty base URI");
            return
                string(
                    abi.encodePacked(
                        tokenConfig.baseURI,
                        tokenId.toString(),
                        ".json"
                    )
                );
        }
    }

    function getRoyaltyConfig()
        external
        view
        returns (NFTDataStructures.RoyaltyConfig memory)
    {
        return royaltyConfig;
    }

    function getTokenConfig()
        external
        view
        returns (NFTDataStructures.TokenConfig memory)
    {
        return tokenConfig;
    }

    function getSaleConfig()
        external
        view
        returns (NFTDataStructures.SaleConfig memory)
    {
        return saleConfig;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721Enumerable, IERC165) returns (bool) {
        return
            interfaceId == type(IERC2981).interfaceId ||
            super.supportsInterface(interfaceId);
    }

    receive() external payable {}
}
