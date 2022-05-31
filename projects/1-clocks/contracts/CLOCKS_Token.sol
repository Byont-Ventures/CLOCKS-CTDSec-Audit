// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract CLOCKS_Token is
    Initializable,
    ERC20Upgradeable,
    UUPSUpgradeable
{
    //=====Access_Management=====//
    address public owner;
    address public treasury;

    //=====Token_Configuration_Constants=====//
    uint256 public constant MAX_SUPPLY = 10**6 * 10**18;

    //=====Events=====//
    event MintedTokens(address to, uint256 amount);
    event UpgradedCLOCKSTokenContract(address newImplementation);
    event OwnershipTransfered(address oldOwner, address newOwner);
    event TreasuryAddressChanged(address oldTreasury, address newTreasury);

    //=====cnstructor_and_initialize=====//

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(address ownerAddress, address treasuryAddress) external initializer {
        require(ownerAddress != address(0), "owner can't be address 0");
        require(treasuryAddress != address(0), "treasury can't be address 0");
        
        __ERC20_init("CLOCKS_Token", "CLK");
        __UUPSUpgradeable_init();

        owner = ownerAddress;
        treasury = treasuryAddress;

        _mint(treasury, 10**4 * 10**18);
    }

    //=====Modifiers=====//

    modifier onlyOwnerRole() {
        require(owner == msg.sender, "Caller != owner");
        _;
    }

    //=====Functions=====//

    function mint(uint256 amount) external onlyOwnerRole {
        require(
            balanceOf(treasury) + amount <= MAX_SUPPLY,
            "Would reach MAX_SUPPLY"
        );

        _mint(treasury, amount);

        emit MintedTokens(treasury, amount);
    }

    function updateOwner(address newOwner) external onlyOwnerRole {
        require(newOwner != address(0), "No address 0");
        
        address oldOwner = owner;
        owner = newOwner;

        emit OwnershipTransfered(oldOwner, owner);
    }

    function updateTreasury(address newTreasury) external onlyOwnerRole {
        require(newTreasury != address(0), "No address 0");
        
        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryAddressChanged(oldTreasury, treasury);
    }

    //=====Necessary_overrides=====//

    /// @notice This function must be overriden for the UUPSUpgradeable contract
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyOwnerRole
    {
        emit UpgradedCLOCKSTokenContract(newImplementation);
    }
}