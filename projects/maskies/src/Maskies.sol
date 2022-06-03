// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
pragma abicoder v2;

import "erc721psi/contracts/ERC721Psi.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

// Using relative paths because hardhat doesn't know about the
// libs folder defined in foundry.toml
import "../lib/Whitelisting/src/Whitelist.sol";

// Date of creation: 2022-06-03T13:02:06.207Z

// Based on contract given in https://www.notion.so/byont/Voorstel-Masky-s-NFT-Fase-1-V2-8f1dc123cca34cdea1a8ac66f35c27b1

contract Maskies is ERC721Psi, Pausable, Ownable, ReentrancyGuard, WhiteList {

    //--------------------------------------------------
    // Constants
    //--------------------------------------------------
    // Sale
    uint256 public constant MAX_TOKENS = 1000;
    uint256 public constant RESERVED_AMOUNT = 100;

    //--------------------------------------------------
    // Variables
    //--------------------------------------------------
    // Sale
    uint256 public maxTotalMintsThisStage = 400;
    uint256 public maxMintBatchAmount = 10;
    uint256 public pricePerToken = 0.05 ether; // (50,000,000,000,000,000) This is the price per token
    uint256 public reservedTokensMinted = 0;
    mapping (address => uint256) public addressMinted;

    // URI
    string public baseTokenURI = '';
    string public unrevealedURI = '';
    bool public revealed = false;

    //--------------------------------------------------
    // Events
    //--------------------------------------------------
    event Mint(address minter, uint256 amount, bytes32[] proof);
    event MintReserved(uint256 amount, address to);
    event SetMaxTotalMintsThisStage(uint256 newMax);
    event SetMaxMintBatchAmount(uint256 newLimit);
    event SetPricePerToken(uint256 newPricePerToken);
    event SetBaseURI();
    event SetUnrevealedURI(string newUnrevealedURI);
    event FlipReleaved(bool newState);
    event WithdrawAmount(uint256 amount);
    event WithdrawAll(uint256 amount);
    event ChangeOwner(address newOwner);

    //--------------------------------------------------
    // Constructor
    //--------------------------------------------------
    constructor() 
        ERC721Psi ("Maskies", "MSK") {
    }

    //--------------------------------------------------
    // Minting
    //--------------------------------------------------
    function mint(address minter, uint256 maxMints, uint256 amount, bytes32[] memory proof) external payable whenNotPaused nonReentrant {
        // Minting amount related
        require(totalSupply() + amount <= maxTotalMintsThisStage, 'Would reach max mints in this stage');
        require(amount <= maxMintBatchAmount, 'Maximum batch size reached');
        require(totalSupply() + amount <= MAX_TOKENS - (RESERVED_AMOUNT - reservedTokensMinted), 'Would reach maximum supply');
        require(addressMinted[minter] + amount <= maxMints, 'Address would exceed balance limit');

        // Price related
        require(msg.value >= pricePerToken * amount, 'Not enough ETH for transaction');

        // Whitelist related
        bytes32 leaf = keccak256(abi.encode(minter, maxMints));
        require(!whitelistIsActive || verifyMerkleProof(proof, leaf), 'Address not whitelisted');

        // The actual mint
        addressMinted[minter] += amount;
        _safeMint(minter, amount);

        emit Mint(minter, amount, proof);
    }

    function mintReserved(uint256 amount, address to) external onlyOwner nonReentrant {
        // Amount > 0 and addres(0) checks are already done in the ERC721Psi._mint() function
        require(reservedTokensMinted + amount <= RESERVED_AMOUNT, 'Would be more than reserved amount');

        reservedTokensMinted += amount;
        _safeMint(to, amount);

        emit MintReserved(amount, to);
    }

    //--------------------------------------------------
    // Sale related
    //--------------------------------------------------
    function setMaxTotalMintsThisStage(uint256 newMax) external onlyOwner {
        require(newMax <= MAX_TOKENS, 'Stage max cannot exceed MAX_TOKENS');

        maxTotalMintsThisStage = newMax;
        emit SetMaxTotalMintsThisStage(maxTotalMintsThisStage);
    }

    function flipWhitelistState() external override onlyOwner {
        _flipWhitelistState();
    }

    function setMaxMintBatchAmount(uint256 newMax) external onlyOwner {
        require(newMax <= MAX_TOKENS, 'Batch max cannot exceed MAX_TOKENS');
        
        maxMintBatchAmount = newMax;
        emit SetMaxMintBatchAmount(maxMintBatchAmount);
    }

    function setPricePerToken(uint256 newPricePerToken) external onlyOwner {
        pricePerToken = newPricePerToken;
        emit SetPricePerToken(pricePerToken);
    }

    //--------------------------------------------------
    // Merkle proof related
    //--------------------------------------------------
    function setMerkleRoot(bytes32 newMerkleRoot)
        external
        override
        onlyOwner
    {
        _setMerkleRoot(newMerkleRoot);
    }

    //--------------------------------------------------
    // URI related
    //--------------------------------------------------
    function _baseURI() internal view virtual override returns (string memory) {
        return baseTokenURI;
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        require(bytes(newBaseURI).length > 0, 'URI cannot be empty');
        baseTokenURI = newBaseURI;
        emit SetBaseURI();
    }

    function setUnrevealedURI(string calldata newUnrevealedURI) external onlyOwner {
        require(bytes(newUnrevealedURI).length > 0, 'URI cannot be empty');
        unrevealedURI = newUnrevealedURI;
        emit SetUnrevealedURI(unrevealedURI);
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), 'URI query for nonexistent token');

        if(!revealed) {
            return unrevealedURI;
        }

        string memory _tokenURI = super.tokenURI(tokenId);
        return bytes(_tokenURI).length > 0 ? string(abi.encodePacked(_tokenURI, ".json")) : "";
    }

    function flipReleaved() external onlyOwner {
        revealed = !revealed;

        emit FlipReleaved(revealed);
    }

    //--------------------------------------------------
    // Withdrawel related
    //--------------------------------------------------
    function withdrawAmount(uint256 amount) external onlyOwner nonReentrant {
        require(amount > 0, 'Amount should be greater than 0');
        uint256 contractBalance = address(this).balance;
        require(amount <= contractBalance, 'Not enough balance in contract');
        
        (bool success, ) = payable(owner()).call{value: amount}("");
        require(success, 'Transfer failed');

        emit WithdrawAmount(amount);
    }

    function withdrawAll() external onlyOwner nonReentrant {
        uint256 contractBalance = address(this).balance;
        require(contractBalance > 0, 'Contract balance is 0');
        
        (bool success, ) = payable(owner()).call{value: contractBalance}("");
        require(success, 'Transfer failed');

        emit WithdrawAll(contractBalance);
    }

    //--------------------------------------------------
    // Owner related
    //--------------------------------------------------
    function changeOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), 'newOwner cannot be address(0)');
        require(newOwner != owner(), 'newowner cannot be current owner');
        transferOwnership(newOwner);

        emit ChangeOwner(newOwner);
    }

    //--------------------------------------------------
    // Pause related
    //--------------------------------------------------
    function pauseContract() external onlyOwner {
        _pause();
    }

    function unpauseContract() external onlyOwner {
        _unpause();
    }
}
