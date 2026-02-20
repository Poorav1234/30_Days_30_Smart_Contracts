// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
    NFT Fractional Ownership Vault (Advanced / Hard-level)

    ✅ What it does:
    - Locks 1 ERC-721 NFT inside a vault (escrow)
    - Mints ERC-20 "fraction" shares (fixed supply)
    - Anyone can start a BUYOUT by depositing full payout upfront
    - After buyout starts:
        - Buyer can claim the NFT after deadline (even if some holders refuse to sell)
        - Fraction holders can redeem (burn) shares anytime to claim their payout
    - Also supports classic "own 100% shares => redeem NFT" when no buyout is active

    ⚠️ Notes:
    - Uses ERC20 payment token for buyout payouts (recommended for production, e.g., USDC)
    - No on-chain governance/voting here (this is the clean forced-buyout model)
*/

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract FractionalNFTVault is ERC20Permit, ERC20Burnable, ReentrancyGuard {
    using Math for uint256;

    // --- NFT held in escrow ---
    IERC721 public immutable nft;
    uint256 public immutable tokenId;

    // --- Buyout payment token (e.g., USDC) ---
    IERC20 public immutable paymentToken;

    // --- Vault creator / curator (optional use) ---
    address public immutable curator;

    // --- Buyout state ---
    struct Buyout {
        address buyer;          // who initiated buyout
        uint96  pricePerShare;  // payment token units per 1 share (fits in uint96)
        uint64  startTime;
        uint64  endTime;
        bool    nftClaimed;     // buyer already claimed NFT?
        uint256 sharesRedeemed; // how many shares have been redeemed (burned) for payout
        uint256 payoutPool;     // total funds deposited for buyout payouts
        bool    active;
    }

    Buyout public buyout;

    // --- Events ---
    event VaultCreated(address indexed curator, address indexed nft, uint256 indexed tokenId, uint256 totalShares);
    event BuyoutStarted(address indexed buyer, uint256 pricePerShare, uint256 startTime, uint256 endTime, uint256 totalDeposited);
    event BuyoutCancelled(address indexed buyer);
    event NFTClaimed(address indexed buyer);
    event SharesRedeemed(address indexed holder, uint256 shares, uint256 payout);
    event NFTRedeemedByFullOwner(address indexed owner);

    // --- Custom errors ---
    error NotOwnerOfShareSupply();
    error BuyoutAlreadyActive();
    error NoActiveBuyout();
    error BuyoutStillRunning();
    error NFTAlreadyClaimed();
    error InsufficientDeposit();
    error InvalidDuration();
    error CancelNotAllowed();
    error ZeroAmount();

    /*
        Constructor flow (typical):
        1) Curator approves this contract for NFT transfer
        2) Deploy vault with nft, tokenId, paymentToken, totalShares
        3) Contract pulls NFT into escrow
        4) Contract mints totalShares to curator
    */
    constructor(
        address _nft,
        uint256 _tokenId,
        address _paymentToken,
        string memory name_,
        string memory symbol_,
        uint256 totalShares_
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        require(_nft != address(0), "nft=0");
        require(_paymentToken != address(0), "paymentToken=0");
        require(totalShares_ > 0, "shares=0");

        nft = IERC721(_nft);
        tokenId = _tokenId;
        paymentToken = IERC20(_paymentToken);
        curator = msg.sender;

        // Mint fixed supply of shares to curator
        _mint(msg.sender, totalShares_);

        emit VaultCreated(msg.sender, _nft, _tokenId, totalShares_);
    }

    // -----------------------------
    // 1) Classic redeem: if you own 100% shares (and no buyout) => get NFT
    // -----------------------------
    function redeemNFTByBurningAllShares() external nonReentrant {
        if (buyout.active) revert BuyoutAlreadyActive();

        uint256 supply = totalSupply();
        if (balanceOf(msg.sender) != supply) revert NotOwnerOfShareSupply();

        // Burn all shares and send NFT
        _burn(msg.sender, supply);
        nft.transferFrom(address(this), msg.sender, tokenId);

        emit NFTRedeemedByFullOwner(msg.sender);
    }

    // -----------------------------
    // 2) Start a forced buyout (deposit full payout upfront)
    // -----------------------------
    /*
        Buyer deposits: totalSupply * pricePerShare
        durationSec controls the buyout window (e.g., 3 days, 7 days, etc.)

        After endTime:
        - buyer can claim NFT
        - holders can still redeem shares for payout anytime (until payout pool exhausted)
    */
    function startBuyout(uint256 pricePerShare, uint64 durationSec) external nonReentrant {
        if (buyout.active) revert BuyoutAlreadyActive();
        if (durationSec < 1 hours || durationSec > 30 days) revert InvalidDuration();
        require(pricePerShare > 0, "price=0");

        uint256 supply = totalSupply();
        uint256 required = supply * pricePerShare;

        // Pull funds from buyer (buyer must approve paymentToken)
        // NOTE: Uses strict "required" funding to guarantee every share can be paid out.
        uint256 beforeBal = paymentToken.balanceOf(address(this));
        bool ok = paymentToken.transferFrom(msg.sender, address(this), required);
        require(ok, "pay transfer failed");
        uint256 received = paymentToken.balanceOf(address(this)) - beforeBal;

        if (received < required) revert InsufficientDeposit();

        buyout = Buyout({
            buyer: msg.sender,
            pricePerShare: uint96(pricePerShare),
            startTime: uint64(block.timestamp),
            endTime: uint64(block.timestamp) + durationSec,
            nftClaimed: false,
            sharesRedeemed: 0,
            payoutPool: required,
            active: true
        });

        emit BuyoutStarted(msg.sender, pricePerShare, block.timestamp, block.timestamp + durationSec, required);
    }

    // Optional: allow buyer to cancel ONLY if nobody redeemed yet
    function cancelBuyout() external nonReentrant {
        if (!buyout.active) revert NoActiveBuyout();
        if (msg.sender != buyout.buyer) revert("not buyer");
        if (buyout.sharesRedeemed != 0) revert CancelNotAllowed();
        if (buyout.nftClaimed) revert CancelNotAllowed();

        uint256 refund = buyout.payoutPool;

        // Reset state first (CEI pattern)
        delete buyout;

        bool ok = paymentToken.transfer(msg.sender, refund);
        require(ok, "refund failed");

        emit BuyoutCancelled(msg.sender);
    }

    // -----------------------------
    // 3) Buyer claims the NFT after deadline (forced buyout)
    // -----------------------------
    function claimNFTAfterBuyout() external nonReentrant {
        if (!buyout.active) revert NoActiveBuyout();
        if (block.timestamp < buyout.endTime) revert BuyoutStillRunning();
        if (msg.sender != buyout.buyer) revert("not buyer");
        if (buyout.nftClaimed) revert NFTAlreadyClaimed();

        buyout.nftClaimed = true;

        // Buyer gets NFT even if some holders refused to sell.

        emit NFTClaimed(msg.sender);
    }

    // -----------------------------
    // 4) Fraction holders redeem shares for payout during/after buyout
    // -----------------------------
    /*
        Holder burns shares and gets:
            payout = shares * pricePerShare

        Works during buyout window and AFTER buyer claims NFT too.
        This is how the "5% holdout" still gets paid later.
    */
    function redeemSharesForPayout(uint256 shares) external nonReentrant {
        if (!buyout.active) revert NoActiveBuyout();
        if (shares == 0) revert ZeroAmount();

        uint256 payout = shares * uint256(buyout.pricePerShare);

        // Ensure pool has enough (it should if funded correctly, but safety anyway)
        require(payout <= buyout.payoutPool, "pool low");

        // Burn shares from holder
        _burn(msg.sender, shares);

        // Update accounting
        buyout.sharesRedeemed += shares;
        buyout.payoutPool -= payout;

        // Pay holder
        bool ok = paymentToken.transfer(msg.sender, payout);
        require(ok, "payout failed");

        emit SharesRedeemed(msg.sender, shares, payout);
    }

    function depositNFT() external nonReentrant {
        // only curator can deposit (optional)
        require(msg.sender == curator, "not curator");

        // pull NFT into escrow (curator must approve vault first)
        nft.transferFrom(msg.sender, address(this), tokenId);
    }

    // -----------------------------
    // View helpers
    // -----------------------------
    function buyoutRequiredDeposit(uint256 pricePerShare) external view returns (uint256) {
        return totalSupply() * pricePerShare;
    }

    function buyoutTimeLeft() external view returns (uint256) {
        if (!buyout.active) return 0;
        if (block.timestamp >= buyout.endTime) return 0;
        return buyout.endTime - block.timestamp;
    }

    function payoutForShares(uint256 shares) external view returns (uint256) {
        if (!buyout.active) return 0;
        return shares * uint256(buyout.pricePerShare);
    }
}