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
 * @dev Implementación de marketplace para NFTs con listados directos y sistema de ofertas
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

    struct Offer {
        address bidder;
        uint256 amount;
        uint256 expirationTime;
        bool isActive;
    }

    // Variables de estado
    uint256 public platformFee;      // Base 10000 (2% = 200)
    mapping(address => mapping(uint256 => Listing)) public listings;
    mapping(address => mapping(uint256 => Offer[])) public offers;
    
    uint256 public totalVolume;
    uint256 public totalListings;
    uint256 public totalSales;
    uint256 public totalOffers;
    bool public isEmergencyMode;
    uint256 public minOfferDuration;
    uint256 public maxOfferDuration;

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

    event OfferCreated(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 amount,
        uint256 expirationTime,
        uint256 timestamp
    );

    event OfferAccepted(
        address indexed nftContract,
        uint256 indexed tokenId,
        address seller,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );

    event OfferCancelled(
        address indexed nftContract,
        uint256 indexed tokenId,
        address indexed bidder,
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
    error InvalidOfferDuration();
    error InvalidOfferAmount();
    error OfferNotFound();
    error OfferExpired();
    error OfferNotActive();
    error UnauthorizedAcceptance();
    error InsufficientOfferBalance();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init();
        
        platformFee = 200; // 2%
        isEmergencyMode = false;
        minOfferDuration = 1 hours;
        maxOfferDuration = 30 days;
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

        uint256 platformFeeAmount = (msg.value * platformFee) / 10000;
        uint256 royaltyAmount;
        address royaltyReceiver;
        uint256 sellerAmount;

        bool supportsRoyalties = IERC2981(nftContract).supportsInterface(type(IERC2981).interfaceId);

        if (supportsRoyalties) {
            (royaltyReceiver, royaltyAmount) = IERC2981(nftContract).royaltyInfo(tokenId, msg.value);
            sellerAmount = msg.value - platformFeeAmount - royaltyAmount;
        } else {
            sellerAmount = msg.value - platformFeeAmount;
        }

        listing.isActive = false;
        totalSales++;
        totalVolume += msg.value;

        IERC721(nftContract).transferFrom(listing.seller, msg.sender, tokenId);

        bool success;

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

        if (supportsRoyalties && royaltyReceiver != address(0) && royaltyAmount > 0) {
            if (royaltyReceiver == nftContract) {
                (success, ) = payable(nftContract).call{value: royaltyAmount}(
                    abi.encodeWithSignature("distributeRoyalties(uint256)", royaltyAmount)
                );
                if (!success) revert TransferFailed();
            } else {
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
     * @notice Crea una oferta por un NFT específico
     */
    function makeOffer(
        address nftContract,
        uint256 tokenId,
        uint256 duration
    ) external payable whenNotPaused nonReentrant {
        if (isEmergencyMode) revert EmergencyModeEnabled();
        if (msg.value == 0) revert InvalidOfferAmount();
        if (duration < minOfferDuration || duration > maxOfferDuration) revert InvalidOfferDuration();
        
        IERC721 nft = IERC721(nftContract);
        try nft.ownerOf(tokenId) returns (address owner) {
            if (owner == msg.sender) revert SellerCannotBuy();
        } catch {
            revert InvalidNFTContract();
        }

        offers[nftContract][tokenId].push(Offer({
            bidder: msg.sender,
            amount: msg.value,
            expirationTime: block.timestamp + duration,
            isActive: true
        }));

        totalOffers++;

        emit OfferCreated(
            nftContract,
            tokenId,
            msg.sender,
            msg.value,
            block.timestamp + duration,
            block.timestamp
        );
    }

    /**
     * @notice Acepta una oferta específica
     */
    function acceptOffer(
        address nftContract,
        uint256 tokenId,
        uint256 offerIndex
    ) external nonReentrant whenNotPaused {
        if (isEmergencyMode) revert EmergencyModeEnabled();

        IERC721 nft = IERC721(nftContract);
        if (nft.ownerOf(tokenId) != msg.sender) revert NotTokenOwner();
        
        Offer storage offer = offers[nftContract][tokenId][offerIndex];
        if (!offer.isActive) revert OfferNotActive();
        if (block.timestamp >= offer.expirationTime) revert OfferExpired();

        uint256 amount = offer.amount;
        uint256 platformFeeAmount = (amount * platformFee) / 10000;
        uint256 royaltyAmount;
        address royaltyReceiver;
        uint256 sellerAmount;

        bool supportsRoyalties = IERC2981(nftContract).supportsInterface(type(IERC2981).interfaceId);
        if (supportsRoyalties) {
            (royaltyReceiver, royaltyAmount) = IERC2981(nftContract).royaltyInfo(tokenId, amount);
            sellerAmount = amount - platformFeeAmount - royaltyAmount;
        } else {
            sellerAmount = amount - platformFeeAmount;
        }

        offer.isActive = false;
        totalSales++;
        totalVolume += amount;

        nft.transferFrom(msg.sender, offer.bidder, tokenId);

        bool success;

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

        if (supportsRoyalties && royaltyReceiver != address(0) && royaltyAmount > 0) {
            if (royaltyReceiver == nftContract) {
                (success, ) = payable(nftContract).call{value: royaltyAmount}(
                    abi.encodeWithSignature("distributeRoyalties(uint256)", royaltyAmount)
                );
                if (!success) revert TransferFailed();
            } else {
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

        (success, ) = payable(msg.sender).call{value: sellerAmount}("");
        if (!success) revert TransferFailed();
        emit PaymentProcessed(
            msg.sender,
            sellerAmount,
            "seller",
            nftContract,
            tokenId,
            block.timestamp
        );

        emit OfferAccepted(
            nftContract,
            tokenId,
            msg.sender,
            offer.bidder,
            amount,
            block.timestamp
        );
    }

    /**
     * @notice Cancela una oferta y devuelve el ETH
     */
    function cancelOffer(
        address nftContract,
        uint256 tokenId,
        uint256 offerIndex
    ) external nonReentrant whenNotPaused {
        Offer storage offer = offers[nftContract][tokenId][offerIndex];
        if (msg.sender != offer.bidder) revert NotSeller();
        if (!offer.isActive) revert OfferNotActive();

        offer.isActive = false;
        
        (bool success, ) = payable(msg.sender).call{value: offer.amount}("");
        if (!success) revert TransferFailed();

        emit OfferCancelled(nftContract, tokenId, msg.sender, block.timestamp);
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

    function setOfferDurationLimits(
        uint256 _minDuration,
        uint256 _maxDuration
    ) external onlyOwner {
        if (_minDuration >= _maxDuration) revert InvalidOfferDuration();
        minOfferDuration = _minDuration;
        maxOfferDuration = _maxDuration;
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

    function getOffers(
        address nftContract,
        uint256 tokenId
    ) external view returns (Offer[] memory) {
        return offers[nftContract][tokenId];
    }

    /**
     * @dev Retorna todas las ofertas activas para un NFT
     */
    function getActiveOffers(
        address nftContract,
        uint256 tokenId
    ) external view returns (Offer[] memory activeOffers) {
        Offer[] memory allOffers = offers[nftContract][tokenId];
        uint256 activeCount = 0;

        // Primer paso: contar ofertas activas
        for (uint256 i = 0; i < allOffers.length; i++) {
            if (allOffers[i].isActive && block.timestamp < allOffers[i].expirationTime) {
                activeCount++;
            }
        }

        // Segundo paso: crear array del tamaño exacto necesario
        activeOffers = new Offer[](activeCount);
        uint256 currentIndex = 0;

        // Tercer paso: llenar array con ofertas activas
        for (uint256 i = 0; i < allOffers.length; i++) {
            if (allOffers[i].isActive && block.timestamp < allOffers[i].expirationTime) {
                activeOffers[currentIndex] = allOffers[i];
                currentIndex++;
            }
        }

        return activeOffers;
    }

    /**
     * @dev Retorna la oferta más alta activa para un NFT
     */
    function getHighestOffer(
        address nftContract,
        uint256 tokenId
    ) external view returns (Offer memory highestOffer, uint256 offerIndex) {
        Offer[] memory allOffers = offers[nftContract][tokenId];
        uint256 highestAmount = 0;
        bool foundActive = false;

        for (uint256 i = 0; i < allOffers.length; i++) {
            if (allOffers[i].isActive && 
                block.timestamp < allOffers[i].expirationTime && 
                allOffers[i].amount > highestAmount) {
                highestOffer = allOffers[i];
                offerIndex = i;
                highestAmount = allOffers[i].amount;
                foundActive = true;
            }
        }

        require(foundActive, "No active offers found");
        return (highestOffer, offerIndex);
    }

    receive() external payable {}
}