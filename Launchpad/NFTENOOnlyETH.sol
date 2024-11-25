// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts@4.8.0/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts@4.8.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.8.0/utils/Strings.sol";
import "@openzeppelin/contracts@4.8.0/security/ReentrancyGuard.sol";

/// @title Custom NFT
/// @notice This contract implements a customizable ERC721 token that can be bought with ETH.
/// @dev Inherits from ERC721Enumerable, Ownable, and ReentrancyGuard.
contract CustomNFT is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    /// @notice Maximum supply of tokens that can be minted.
    uint256 public max_supply;
    /// @notice Price of each NFT in ETH.
    uint256 public NFTPriceInETH;
    /// @notice ID for the next token to be minted.
    uint256 private _tokenId = 1;

    /// @notice Address of the owner wallet.
    address public immutable ownerWallet;
    /// @notice Address of the commission wallet.
    address public immutable commissionWallet;
    /// @notice Mapping to track the number of tokens minted by each address.
    mapping(address => uint256) private _mintedCount;

    /// @notice Timestamp when the sale starts.
    uint256 public immutable saleStartTime;
    /// @notice Maximum number of mints allowed per wallet.
    uint256 public immutable maxMintsPerWallet;

    /// @notice Indicates if the same metadata is used for all tokens.
    bool public immutable sameMetadataForAll;
    /// @notice Commission percentage for each sale.
    uint256 public immutable commission;
    /// @notice Base URI for token metadata.
    string public baseURI;
    /// @notice Common metadata URI for all tokens.
    string public commonMetadataURI;

    /// @notice Emitted when the NFT price in ETH is set.
    /// @param newPrice New price for the NFT in ETH.
    event NFTPriceSet(uint256 newPrice);
    /// @notice Emitted when the maximum supply is set.
    /// @param newSupply New maximum supply.
    event MaxSupplySet(uint256 newSupply);
    /// @notice Emitted when an NFT is bought and minted.
    /// @param buyer Address of the buyer.
    /// @param tokenId ID of the minted token.
    /// @param price Price paid in ETH.
    event NFTBoughtAndMinted(
        address indexed buyer,
        uint256 tokenId,
        uint256 price
    );
    /// @notice Emitted when funds are withdrawn.
    /// @param commissionAmount Amount sent to the commission wallet.
    /// @param ownerAmount Amount sent to the owner wallet.
    event FundsWithdrawn(uint256 commissionAmount, uint256 ownerAmount);

    /// @notice Constructor to initialize the contract with required parameters.
    /// @param _name Name of the NFT collection.
    /// @param _symbol Symbol of the NFT collection.
    /// @param _commissionWallet Address of the commission wallet.
    /// @param _ownerWallet Address of the owner wallet.
    /// @param _saleStartTime Timestamp when the sale starts.
    /// @param _maxMintsPerWallet Maximum mints allowed per wallet.
    /// @param _maxSupply Maximum supply of tokens.
    /// @param _NFTPriceInETH Price of each NFT in ETH.
    /// @param _sameMetadataForAll Indicates if the same metadata is used for all tokens.
    /// @param _commission Commission percentage for each sale.
    /// @param _metadataURI URI for the NFT metadata.
    constructor(
        string memory _name,
        string memory _symbol,
        address _commissionWallet,
        address _ownerWallet,
        uint256 _saleStartTime,
        uint256 _maxMintsPerWallet,
        uint256 _maxSupply,
        uint256 _NFTPriceInETH,
        bool _sameMetadataForAll,
        uint256 _commission,
        string memory _metadataURI
    ) ERC721(_name, _symbol) Ownable() {
        require(
            _commissionWallet != address(0),
            "Commission wallet address cannot be zero"
        );
        require(
            _ownerWallet != address(0),
            "Owner wallet address cannot be zero"
        );

        commissionWallet = _commissionWallet;
        ownerWallet = _ownerWallet;
        saleStartTime = _saleStartTime;
        maxMintsPerWallet = _maxMintsPerWallet;
        max_supply = _maxSupply;
        NFTPriceInETH = _NFTPriceInETH;
        sameMetadataForAll = _sameMetadataForAll;
        commission = _commission;

        if (sameMetadataForAll) {
            commonMetadataURI = _metadataURI;
        } else {
            baseURI = _metadataURI;
        }
    }

    /// @notice Function to get the URI of a token.
    /// @param tokenId ID of the token.
    /// @return string URI of the token metadata.
    /// @dev Requires the token to exist.
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        require(
            _exists(tokenId),
            "ERC721Metadata: URI query for nonexistent token"
        );

        if (sameMetadataForAll) {
            return commonMetadataURI;
        } else {
            return
                string(abi.encodePacked(baseURI, tokenId.toString(), ".json"));
        }
    }

    /// @notice Function to buy an NFT with ETH.
    /// @dev Transfers ETH from the buyer to the contract, then mints a new NFT.
    function buyNFTWithETH() public payable nonReentrant {
        require(block.timestamp >= saleStartTime, "Sale has not started yet");
        require(msg.value == NFTPriceInETH, "Incorrect ETH amount sent");

        uint256 mintedCount = _mintedCount[msg.sender];
        require(mintedCount < maxMintsPerWallet, "Exceeds maximum NFTs");

        _mintedCount[msg.sender] = mintedCount + 1;

        uint256 newTokenId = _tokenId;
        require(newTokenId <= max_supply, "Max supply reached");
        _mint(msg.sender, newTokenId);
        _tokenId++;

        emit NFTBoughtAndMinted(msg.sender, newTokenId, msg.value);
    }

    /// @notice Function to withdraw accumulated funds to the commission and owner wallets.
    function withdraw() public nonReentrant {
        require(
            msg.sender == commissionWallet || msg.sender == ownerWallet,
            "Caller is not authorized"
        );

        uint256 balance = address(this).balance;
        uint256 commissionAmount = (balance * commission) / 100;
        uint256 ownerAmount = balance - commissionAmount;

        (bool successCommission, ) = commissionWallet.call{
            value: commissionAmount
        }("");
        require(successCommission, "Transfer to commission wallet failed");

        (bool successOwner, ) = ownerWallet.call{value: ownerAmount}("");
        require(successOwner, "Transfer to owner wallet failed");

        emit FundsWithdrawn(commissionAmount, ownerAmount);
    }

    // Function to receive ETH
    receive() external payable {}
}
