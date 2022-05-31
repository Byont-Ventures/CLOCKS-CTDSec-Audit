// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./libraries/Timer.sol";

contract CLOCKS_OTC is Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    //=====Access_Management=====//
    address public owner;
    address public treasury;

    //=====Token=====//
    IERC20 public OTHER_token;
    IERC20 public CLK_token;

    uint256 public one_CLK_token;

    //=====Transaction_configuration=====//
    Timer.Window public transactionWindow;

    uint256 public buyRate;
    uint256 public sellRate;
    uint256 public maxBuyAmountCLK;
    uint256 public maxSellAmountCLK;

    //=====Events=====//

    // TransactionWindowChanged is emitted from the Timer library. But to emit the event,
    // it should also be defined in the contract here.
    event TransactionWindowChanged(
        uint256 oldStart,
        uint256 oldStop,
        uint256 newStart,
        uint256 newStop
    );
    event BuyEvent(uint256 amountUSDC, uint256 amountCLK, address buyerAddress);
    event SellEvent(
        uint256 amountCLK,
        uint256 amountUSDC,
        address sellerAddress
    );
    event BuyRateChanged(uint256 oldRate, uint256 newRate);
    event SellRateChanged(uint256 oldRate, uint256 newRate);
    event MaxBuyAmountClkChanged(uint256 oldMax, uint256 newMax);
    event MaxSellAmountClkChanged(uint256 oldMax, uint256 newMax);
    event OwnershipTransfered(address oldOwner, address newOwner);
    event TreasuryAddressTransfered(address oldTreasury, address newTreasury);
    event WithdrawnCLK(address from, address to, uint256 amount);
    event WithdrawnOTHER(address from, address to, uint256 amount);

    constructor(
        address ownerAddress,
        address treasuryAddress,
        address otherTokenAddress,
        address clkTokenAddress,
        uint256 initialBuyRate,
        uint256 initialSellRate,
        uint256 initialMaxBuyAmountCLK,
        uint256 initialMaxSellAmountCLK
    ) Pausable() {
        require(ownerAddress != address(0), "Owner can't be address 0");
        require(treasuryAddress != address(0), "Treasury can't be address 0");
        require(otherTokenAddress != address(0), "OTHER can't be address 0");
        require(clkTokenAddress != address(0), "CLK can't be address 0");
        require(initialBuyRate > 0, "buyRate should be >0");
        require(initialSellRate > 0, "sellRate should be >0");

        OTHER_token = IERC20(otherTokenAddress);
        CLK_token = IERC20(clkTokenAddress);

        one_CLK_token = 10**18;

        transactionWindow.startTime = 0;
        transactionWindow.stopTime = 0;

        owner = ownerAddress;
        treasury = treasuryAddress;

        buyRate = initialBuyRate;
        sellRate = initialSellRate;
        maxBuyAmountCLK = initialMaxBuyAmountCLK;
        maxSellAmountCLK = initialMaxSellAmountCLK;
    }

    //=====Modifiers=====//

    modifier onlyOwnerRole() {
        require(owner == msg.sender, "Caller != owner");
        _;
    }

    modifier windowIsOpen() {
        require(
            Timer.currentTimeIsInWindow(transactionWindow),
            "Buy/sell window closed"
        );
        _;
    }

    //=====Functions=====//

    //-----Transaction-----//
    /// @notice A user buys CLK tokens with another token.
    /// @param amountCLK: The amount of CLK tokens to buy in the smallest unit.
    function buy(uint256 amountCLK) external nonReentrant whenNotPaused windowIsOpen {
        require(amountCLK <= maxBuyAmountCLK, "amountCLK > maxBuyAmountCLK");
        require(
            CLK_token.balanceOf(treasury) >= amountCLK,
            "Not enough CLK available"
        );

        address buyer = msg.sender;

        uint256 amountOTHER = (amountCLK * buyRate)/ one_CLK_token;
        require(
            OTHER_token.balanceOf(buyer) >= amountOTHER,
            "You don't have enough OTHER"
        );

        OTHER_token.safeTransferFrom(buyer, treasury, amountOTHER);
        CLK_token.safeTransferFrom(treasury, buyer, amountCLK);

        emit BuyEvent(amountOTHER, amountCLK, buyer);
    }

    /// @notice A user sells CLK tokens and receives another token.
    /// @param amountCLK: The amount of CLK tokens to buy in the smallest unit.
    function sell(uint256 amountCLK) external nonReentrant whenNotPaused windowIsOpen {
        require(amountCLK <= maxSellAmountCLK, "amountCLK > maxSellAmountCLK");

        address seller = msg.sender;
        require(
            CLK_token.balanceOf(seller) >= amountCLK,
            "You don't have enough CLK"
        );

        uint256 amountOTHER = (amountCLK * sellRate)/ one_CLK_token;
        require(
            OTHER_token.balanceOf(treasury) >= amountOTHER,
            "Not enough OTHER available"
        );

        CLK_token.safeTransferFrom(seller, treasury, amountCLK);
        OTHER_token.safeTransferFrom(treasury, seller, amountOTHER);

        emit SellEvent(amountCLK, amountOTHER, seller);
    }

    function withdrawCLK() external nonReentrant onlyOwnerRole {
        uint256 balance = CLK_token.balanceOf(treasury);
        CLK_token.safeTransferFrom(treasury, owner, balance);

        emit WithdrawnCLK(treasury, owner, balance);
    }

    function withdrawOTHER() external nonReentrant onlyOwnerRole {
        uint256 balance = OTHER_token.balanceOf(treasury);
        OTHER_token.safeTransferFrom(treasury, owner, balance);

        emit WithdrawnOTHER(treasury, owner, balance);
    }

    //-----Cofiguration-----//

    function pauseContract() external onlyOwnerRole {
        _pause();
    }

    function unpauseContract() external onlyOwnerRole {
        _unpause();
    }

    function setTransactionWindow(uint256 startTime, uint256 stopTime)
        external
        onlyOwnerRole
    {
        Timer.setWindow(transactionWindow, startTime, stopTime);
    }

    function getMinimumTransactionWindow() external pure returns (uint256) {
        return Timer.minimumWindowDuration;
    }

    /// @param other_clk_rate: How many of the other token in the smallest unit is needed for 1 CLOCKS token.
    function setBuyRate(uint256 other_clk_rate) external onlyOwnerRole {
        require(other_clk_rate > 0, "Buy rate should be >0");

        uint256 oldRate = buyRate;
        buyRate = other_clk_rate;

        emit BuyRateChanged(oldRate, other_clk_rate);
    }

    /// @param other_clk_rate: how many of the other token in the smallest unit is needed for 1 CLOCKS token.
    function setSellRate(uint256 other_clk_rate) external onlyOwnerRole {
        require(other_clk_rate > 0, "Sell rate should be >0");

        uint256 oldRate = sellRate;
        sellRate = other_clk_rate;

        emit SellRateChanged(oldRate, other_clk_rate);
    }

    function setMaxBuyAmountCLK(uint256 newMaxBuyAmountCLK)
        external
        onlyOwnerRole
    {
        uint256 oldMaxAmountCLK = maxBuyAmountCLK;
        maxBuyAmountCLK = newMaxBuyAmountCLK;

        emit MaxBuyAmountClkChanged(oldMaxAmountCLK, newMaxBuyAmountCLK);
    }

    function setMaxSellAmountCLK(uint256 newMaxSellAmountCLK)
        external
        onlyOwnerRole
    {
        uint256 oldMaxAmountCLK = maxSellAmountCLK;
        maxSellAmountCLK = newMaxSellAmountCLK;

        emit MaxSellAmountClkChanged(oldMaxAmountCLK, newMaxSellAmountCLK);
    }

    //-----Ownership-----//

    function updateOwner(address newOwner) external onlyOwnerRole {
        require(newOwner != address(0), "newOwner != 0");

        address oldOwner = owner;
        owner = newOwner;

        emit OwnershipTransfered(oldOwner, owner);
    }

    function updateTreasury(address newTreasury) external onlyOwnerRole {
        require(newTreasury != address(0), "newTreasury != 0");

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryAddressTransfered(oldTreasury, treasury);
    }
}
