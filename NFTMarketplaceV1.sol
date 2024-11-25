// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable@4.8.0/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable@4.8.0/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts@4.8.0/token/ERC721/IERC721.sol";

/**
 * @title NFT Marketplace V1
 * @dev Implementación básica de marketplace para NFTs con sistema de comisiones
 */
interface ICustomNFT is IERC721 {
    function owner() external view returns (address);
}

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
    uint256 public creatorFee;       // Base 10000 (2% = 200)
    
    mapping(address => mapping(uint256 => Listing)) public listings;
    mapping(address => uint256) public pendingPayments;
    
    uint256 public totalVolume;
    uint256 public totalListings;
    uint256 public totalSales;
    bool public isEmergencyMode;

    // Eventos
    event TokenListed(address indexed nftContract, uint256 indexed tokenId, address indexed seller, uint256 price, uint256 timestamp);
    event TokenSold(
        address indexed nftContract, 
        uint256 indexed tokenId, 
        address seller, 
        address indexed buyer, 
        uint256 price,
        uint256 platformFeeAmount,
        uint256 creatorFeeAmount,
        uint256 timestamp
    );
    event ListingCancelled(address indexed nftContract, uint256 indexed tokenId, address indexed seller, uint256 timestamp);
    event PriceUpdated(address indexed nftContract, uint256 indexed tokenId, uint256 oldPrice, uint256 newPrice);
    event PaymentWithdrawn(address indexed user, uint256 amount, string paymentType);
    event EmergencyModeActivated(uint256 timestamp);
    event EmergencyModeDeactivated(uint256 timestamp);
    event FeeUpdated(string feeType, uint256 oldFee, uint256 newFee);
    event PaymentReceived(address indexed user, uint256 amount, string paymentType);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() public initializer {
        __ReentrancyGuard_init();
        __Pausable_init();
        __Ownable_init();
        
        platformFee = 200; // 2%
        creatorFee = 200;  // 2%
        isEmergencyMode = false;
    }

    /**
     * @notice Lista un NFT para venta
     * @param nftContract Dirección del contrato NFT
     * @param tokenId ID del token
     * @param price Precio en ETH (en wei)
     */
    function listToken(
        address nftContract,
        uint256 tokenId,
        uint256 price
    ) external whenNotPaused {
        require(!isEmergencyMode, "Emergency mode: Listing disabled");
        require(price > 0, "Price must be greater than 0");
        require(nftContract != address(0), "Invalid NFT contract");
        require(msg.sender != address(0), "Invalid sender address");
        
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(
            nft.getApproved(tokenId) == address(this) ||
            nft.isApprovedForAll(msg.sender, address(this)),
            "Marketplace not approved"
        );

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
     * @notice Compra un NFT listado
     * @param nftContract Dirección del contrato NFT
     * @param tokenId ID del token
     */
    function buyToken(
        address nftContract,
        uint256 tokenId
    ) external payable nonReentrant whenNotPaused {
        require(!isEmergencyMode, "Emergency mode: Buying disabled");
        
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.isActive, "Listing not active");
        require(msg.value == listing.price, "Incorrect price");
        require(msg.sender != listing.seller, "Seller cannot buy");

        // Verificar que el contrato tiene suficiente balance
        require(address(this).balance >= msg.value, "Insufficient contract balance");

        // Calcular fees
        uint256 platformFeeAmount = (msg.value * platformFee) / 10000;
        uint256 creatorFeeAmount = (msg.value * creatorFee) / 10000;
        uint256 sellerAmount = msg.value - platformFeeAmount - creatorFeeAmount;

        // Actualizar estado
        listing.isActive = false;
        totalSales++;
        totalVolume += msg.value;

        // Asignar pagos
        address creator = ICustomNFT(nftContract).owner();
        
        // Platform fee siempre va a pendingPayments del owner
        pendingPayments[owner()] += platformFeeAmount;
        emit PaymentReceived(owner(), platformFeeAmount, "platform");

        // Creator fee
        if (creator != address(0)) {
            pendingPayments[creator] += creatorFeeAmount;
            emit PaymentReceived(creator, creatorFeeAmount, "creator");
        } else {
            pendingPayments[owner()] += creatorFeeAmount;
            emit PaymentReceived(owner(), creatorFeeAmount, "platform");
        }

        // Seller amount
        pendingPayments[listing.seller] += sellerAmount;
        emit PaymentReceived(listing.seller, sellerAmount, "seller");

        // Transferir NFT
        IERC721(nftContract).transferFrom(listing.seller, msg.sender, tokenId);

        emit TokenSold(
            nftContract,
            tokenId,
            listing.seller,
            msg.sender,
            msg.value,
            platformFeeAmount,
            creatorFeeAmount,
            block.timestamp
        );
    }

    /**
     * @notice Retira los pagos pendientes
     */
    function withdrawPayments() external nonReentrant {
        uint256 amount = pendingPayments[msg.sender];
        require(amount > 0, "No pending payments");
        require(address(this).balance >= amount, "Insufficient contract balance");
        
        pendingPayments[msg.sender] = 0;
        
        (bool success, ) = payable(msg.sender).call{value: amount}("");
        require(success, "Transfer failed");

        string memory paymentType = msg.sender == owner() ? "platform" : "other";
        emit PaymentWithdrawn(msg.sender, amount, paymentType);
    }

    /**
     * @notice Cancela un listing
     */
    function cancelListing(
        address nftContract,
        uint256 tokenId
    ) external whenNotPaused {
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.seller == msg.sender, "Not the seller");
        require(listing.isActive, "Listing not active");

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
        require(newPrice > 0, "Price must be greater than 0");
        
        Listing storage listing = listings[nftContract][tokenId];
        require(listing.seller == msg.sender, "Not the seller");
        require(listing.isActive, "Listing not active");

        uint256 oldPrice = listing.price;
        listing.price = newPrice;

        emit PriceUpdated(nftContract, tokenId, oldPrice, newPrice);
    }

    // Funciones administrativas esenciales
    function setPlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        uint256 oldFee = platformFee;
        platformFee = newFee;
        emit FeeUpdated("platform", oldFee, newFee);
    }

    function setCreatorFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee too high"); // Max 10%
        uint256 oldFee = creatorFee;
        creatorFee = newFee;
        emit FeeUpdated("creator", oldFee, newFee);
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

    // Funciones de vista esenciales
    function getListing(
        address nftContract,
        uint256 tokenId
    ) external view returns (Listing memory) {
        return listings[nftContract][tokenId];
    }

    function getPendingPayments(address user) external view returns (uint256) {
        return pendingPayments[user];
    }

    function getFees() external view returns (uint256, uint256) {
        return (platformFee, creatorFee);
    }

    receive() external payable {}
}