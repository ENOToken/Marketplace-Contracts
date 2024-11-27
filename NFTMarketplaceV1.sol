// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable@4.8.0/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts@4.8.0/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts@4.8.0/interfaces/IERC2981.sol";

/**
 * @title NFT Marketplace V1
 * @dev Implementación de marketplace para NFTs con pagos automáticos y soporte EIP-2981
 */
contract NFTMarketplaceV1 is Initializable, ReentrancyGuardUpgradeable, PausableUpgradeable, OwnableUpgradeable {
    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        bool isActive;
        uint256 listedTimestamp;
    }

    // Variables de estado
    uint256 public platformFee;      // Base 10000 (2% = 200)
    mapping(address => mapping(uint256 => Listing)) public listings;
    
    uint256 public totalVolume;
    uint256 public totalListings;
    uint256 public totalSales;
    bool public isEmergencyMode;

    // Eventos
    event TokenListed(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        address indexed seller, 
        uint256 price, 
        uint256 timestamp
    );

    event TokenSold(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        address seller, 
        address indexed buyer, 
        uint256 price,
        uint256 timestamp
    );

    event PaymentProcessed(
        address indexed recipient,
        uint256 amount,
        string paymentType,
        address indexed nftContract,
        uint256 indexed tokenId,
        uint256 timestamp
    );

    event ListingCancelled(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        address indexed seller, 
        uint256 timestamp
    );

    event PriceUpdated(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        uint256 oldPrice, 
        uint256 newPrice,
        uint256 timestamp
    );

    event EmergencyModeActivated(uint256 timestamp);
    event EmergencyModeDeactivated(uint256 timestamp);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee, uint256 timestamp);

    // Custom errors
    error InvalidPrice();
    error InvalidNFTContract();
    error InvalidSender();
    error NotTokenOwner();
    error MarketplaceNotApproved();
    error ListingNotActive();
    error IncorrectPrice();
    error SellerCannotBuy();
    error TransferFailed();
    error EmergencyModeEnabled();
    error FeeTooHigh();
    error NotSeller();
    error UnsupportedNFTContract();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init();
        
        platformFee = 200; // 2%
        isEmergencyMode = false;
    }

    /**
     * @notice Lista un NFT para venta
     */
    function listToken(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external whenNotPaused {
        if (isEmergencyMode) revert EmergencyModeEnabled();
        if (price == 0) revert InvalidPrice();
        if (nftContract == address(0)) revert InvalidNFTContract();
        if (msg.sender == address(0)) revert InvalidSender();
        
        IERC721 nft = IERC721(nftContract);
        if (nft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        if (nft.getApproved(tokenId) != address(this) && 
            !nft.isApprovedForAll(msg.sender, address(this))) {
            revert MarketplaceNotApproved();
        }

        listings[nftContract][tokenId] = Listing({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            price: price,
            isActive: true,
            listedTimestamp: block.timestamp
        });

        totalListings++;

        emit TokenListed(nftContract, tokenId, msg.sender, price, block.timestamp);
    }

    /**
     * @notice Compra un NFT listado con pagos automáticos
     */
    function buyToken(
        address nftContract,
        uint256 tokenId
    ) external payable nonReentrant whenNotPaused {
        if (isEmergencyMode) revert EmergencyModeEnabled();
        
        Listing storage listing = listings[nftContract][tokenId];
        if (!listing.isActive) revert ListingNotActive();
        if (msg.value != listing.price) revert IncorrectPrice();
        if (msg.sender == listing.seller) revert SellerCannotBuy();

        // Calcular platform fee
        uint256 platformFeeAmount = (msg.value * platformFee) / 10000;
        uint256 royaltyAmount;
        address royaltyReceiver;
        uint256 sellerAmount;

        // Verificar si el contrato soporta EIP-2981
        bool supportsRoyalties = IERC2981(nftContract).supportsInterface(type(IERC2981).interfaceId);

        if (supportsRoyalties) {
            // Calcular regalías usando EIP-2981
            (royaltyReceiver, royaltyAmount) = IERC2981(nftContract).royaltyInfo(tokenId, msg.value);
            sellerAmount = msg.value - platformFeeAmount - royaltyAmount;
        } else {
            // Si no soporta EIP-2981, todo va al vendedor después del platform fee
            sellerAmount = msg.value - platformFeeAmount;
        }

        // Actualizar estado
        listing.isActive = false;
        totalSales++;
        totalVolume += msg.value;

        // Transferir NFT primero (Check-Effects-Interactions pattern)
        IERC721(nftContract).transferFrom(listing.seller, msg.sender, tokenId);

        // Procesar pagos
        bool success;

        // Platform fee payment
        (success, ) = payable(owner()).call{value: platformFeeAmount}("");
        if (!success) revert TransferFailed();
        emit PaymentProcessed(
            owner(),
            platformFeeAmount,
            "platform",
            nftContract,
            tokenId,
            block.timestamp
        );

        // Royalty payment si aplica
        if (supportsRoyalties && royaltyReceiver != address(0) && royaltyAmount > 0) {
            if (royaltyReceiver == nftContract) {
                // Si el receptor es el contrato NFT, llamamos a distributeRoyalties
                (success, ) = payable(nftContract).call{value: royaltyAmount}(
                    abi.encodeWithSignature("distributeRoyalties(uint256)", royaltyAmount)
                );
                if (!success) revert TransferFailed();
            } else {
                // Caso tradicional de EIP-2981
                (success, ) = payable(royaltyReceiver).call{value: royaltyAmount}("");
                if (!success) revert TransferFailed();
                emit PaymentProcessed(
                    royaltyReceiver,
                    royaltyAmount,
                    "royalty",
                    nftContract,
                    tokenId,
                    block.timestamp
                );
            }
        }

        // Seller payment
        (success, ) = payable(listing.seller).call{value: sellerAmount}("");
        if (!success) revert TransferFailed();
        emit PaymentProcessed(
            listing.seller,
            sellerAmount,
            "seller",
            nftContract,
            tokenId,
            block.timestamp
        );

        emit TokenSold(
            nftContract,
            tokenId,
            listing.seller,
            msg.sender,
            msg.value,
            block.timestamp
        );
    }

    /**
     * @notice Cancela un listing
     */
    function cancelListing(
        address nftContract,
        uint256 tokenId
    ) external whenNotPaused {
        Listing storage listing = listings[nftContract][tokenId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.isActive) revert ListingNotActive();

        listing.isActive = false;

        emit ListingCancelled(nftContract, tokenId, msg.sender, block.timestamp);
    }

    /**
     * @notice Actualiza el precio de un listing
     */
    function updatePrice(
        address nftContract,
        uint256 tokenId,
        uint256 newPrice
    ) external whenNotPaused {
        if (newPrice == 0) revert InvalidPrice();
        
        Listing storage listing = listings[nftContract][tokenId];
        if (listing.seller != msg.sender) revert NotSeller();
        if (!listing.isActive) revert ListingNotActive();

        uint256 oldPrice = listing.price;
        listing.price = newPrice;

        emit PriceUpdated(nftContract, tokenId, oldPrice, newPrice, block.timestamp);
    }

    // Funciones administrativas
    function setPlatformFee(uint256 newFee) external onlyOwner {
        if (newFee > 1000) revert FeeTooHigh(); // Max 10%
        uint256 oldFee = platformFee;
        platformFee = newFee;
        emit PlatformFeeUpdated(oldFee, newFee, block.timestamp);
    }

    function setEmergencyMode(bool enabled) external onlyOwner {
        isEmergencyMode = enabled;
        if (enabled) {
            emit EmergencyModeActivated(block.timestamp);
        } else {
            emit EmergencyModeDeactivated(block.timestamp);
        }
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // Funciones de vista
    function getListing(
        address nftContract,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return listings[nftContract][tokenId];
    }

    receive() external payable {}
}