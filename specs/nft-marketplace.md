# NFT Marketplace Spec

## 1. Overview

A minimal but functional NFT marketplace serving as a test project for the etherform CI/CD framework.

**Goals:**
- Exercise etherform's full capabilities: deployment, upgrade safety validation, and state management
- Provide a realistic contract system with upgradeable proxies
- Define a clear V1 → V2 upgrade path to test storage layout compatibility checks

**Contracts:**
- `SimpleNFT` — an upgradeable ERC721 token
- `Marketplace` — an upgradeable NFT marketplace with escrow-based listings

Both contracts sit behind a `TransparentUpgradeableProxy`, managed by a shared `ProxyAdmin`.

---

## 2. Contract Architecture (V1)

### SimpleNFT.sol — Upgradeable ERC721

**Inherits:** `ERC721Upgradeable`, `Ownable2StepUpgradeable`

**Storage:**
```solidity
uint256 private _nextTokenId;
```

**Functions:**

| Function | Access | Description |
|---|---|---|
| `initialize(string name, string symbol, address owner)` | `initializer` | Sets token name/symbol, transfers ownership |
| `safeMint(address to) → uint256` | `onlyOwner` | Mints the next token ID to `to`, returns the minted ID |

- Token IDs auto-increment starting from 0.
- `_disableInitializers()` in the constructor to prevent implementation initialization.

---

### Marketplace.sol — Upgradeable NFT Marketplace

**Inherits:** `OwnableUpgradeable`, `ReentrancyGuardUpgradeable`

**Core Types:**
```solidity
struct Listing {
    address seller;
    address nftContract;
    uint256 tokenId;
    uint256 price;
    bool active;
}
```

**Storage:**
```solidity
uint256 private _nextListingId;
mapping(uint256 => Listing) public listings;
// reverse lookup: nftContract => tokenId => listingId
mapping(address => mapping(uint256 => uint256)) private _activeListingId;
```

**Functions:**

| Function | Access | Description |
|---|---|---|
| `initialize(address owner)` | `initializer` | Sets owner |
| `listNFT(address nftContract, uint256 tokenId, uint256 price) → uint256` | public | Transfers NFT to contract, creates listing |
| `buyNFT(uint256 listingId)` | `payable`, `nonReentrant` | Pays seller, transfers NFT to buyer |
| `cancelListing(uint256 listingId)` | public | Returns NFT to seller, deactivates listing |

**Events:**
```solidity
event NFTListed(uint256 indexed listingId, address indexed seller, address indexed nftContract, uint256 tokenId, uint256 price);
event NFTSold(uint256 indexed listingId, address indexed buyer, uint256 price);
event ListingCancelled(uint256 indexed listingId);
```

**Custom Errors:**
```solidity
error PriceCannotBeZero();
error ListingNotActive();
error InsufficientPayment();
error NotSeller();
error TransferFailed();
```

**Listing flow:**
1. Seller approves Marketplace to transfer the NFT
2. `listNFT` transfers the NFT into the Marketplace (escrow)
3. A `Listing` struct is stored and the listing ID is returned

**Buy flow:**
1. Buyer calls `buyNFT{value: price}(listingId)`
2. Contract verifies listing is active and `msg.value >= price`
3. Listing is marked inactive (effects before interactions)
4. NFT is transferred to buyer
5. ETH is sent to seller
6. Excess ETH (if any) is refunded to buyer

**Cancel flow:**
1. Seller calls `cancelListing(listingId)`
2. Contract verifies `msg.sender == listing.seller` and listing is active
3. Listing is marked inactive
4. NFT is returned to seller

---

## 3. V2 Upgrade Path

Upgrades append new storage variables after all V1 storage. No existing storage slots are modified.

### MarketplaceV2.sol

Adds a fee mechanism on sales.

**New storage (appended):**
```solidity
uint256 public feePercentage;   // basis points (e.g. 250 = 2.5%)
address public feeRecipient;
uint256 public accumulatedFees;
```

**New/modified functions:**

| Function | Description |
|---|---|
| `reinitialize(uint256 _feePercentage, address _feeRecipient)` | `reinitializer(2)` — sets fee params |
| `buyNFT(uint256 listingId)` | Modified — deducts fee from sale price before paying seller |
| `withdrawFees()` | Transfers `accumulatedFees` to `feeRecipient`, resets accumulator |

**Fee calculation in `buyNFT`:**
```solidity
uint256 fee = (price * feePercentage) / 10_000;
uint256 sellerProceeds = price - fee;
accumulatedFees += fee;
```

### SimpleNFTV2.sol

Adds base URI support and a max supply cap.

**New storage (appended):**
```solidity
string private _baseTokenURI;
uint256 public maxSupply;
```

**New/modified functions:**

| Function | Description |
|---|---|
| `reinitialize(string baseURI_, uint256 maxSupply_)` | `reinitializer(2)` — sets URI and cap |
| `_baseURI() → string` | Override — returns `_baseTokenURI` |
| `safeMint(address to)` | Modified — reverts if `_nextTokenId >= maxSupply` |

---

## 4. Deployment

### Entry Point

Canonical deploy script: `script/Deploy.s.sol:Deploy`

### Deployment Order

1. Deploy `ProxyAdmin` (owned by deployer)
2. Deploy `SimpleNFT` implementation
3. Deploy `TransparentUpgradeableProxy` pointing to SimpleNFT impl, with `initialize(name, symbol, owner)` call
4. Deploy `Marketplace` implementation
5. Deploy `TransparentUpgradeableProxy` pointing to Marketplace impl, with `initialize(owner)` call

### foundry.toml Requirements

```toml
[profile.default]
bytecode_hash = "none"
cbor_metadata = false
build_info = true
ffi = true
ast = true
extra_output = ["storageLayout"]
```

These settings are required for etherform's upgrade safety validation:
- `bytecode_hash = "none"` and `cbor_metadata = false` — deterministic bytecode for deployment verification
- `build_info = true`, `ast = true` — enable OZ Upgrades plugin analysis
- `extra_output = ["storageLayout"]` — storage layout diffing for upgrade safety
- `ffi = true` — required by OZ Foundry Upgrades plugin

---

## 5. Upgrade Validation

### Upgrade Script

`script/upgrades/ValidateUpgrade.s.sol` — uses the OpenZeppelin Foundry Upgrades plugin to validate storage layout compatibility.

**Responsibilities:**
- Load baseline storage layout snapshots for V1 contracts
- Compare against V2 implementation storage layouts
- Fail if any storage collisions, reordering, or type changes are detected
- Validate that new storage is only appended (no gaps, no overwrites)

This script is the primary target for etherform's upgrade safety CI checks.

---

## 6. Security Considerations

- **Reentrancy protection:** `buyNFT` uses `nonReentrant` modifier to prevent reentrant calls during ETH transfers
- **Checks-effects-interactions:** state is updated before external calls (NFT transfers, ETH sends) in all functions
- **Escrow model:** NFTs are held by the contract during listing, avoiding approval front-running attacks where a seller could transfer the NFT after approval but before purchase
- **Access control:**
  - `SimpleNFT.safeMint` is restricted to the owner via `Ownable2StepUpgradeable`
  - `cancelListing` is restricted to the original seller
  - `withdrawFees` (V2) is restricted to the fee recipient
- **ETH handling:** `buyNFT` refunds excess ETH to prevent overpayment loss; seller payment uses low-level `call` with success check

---

## 7. Test Plan

### Unit Tests

- **Listing:** mint NFT → approve marketplace → `listNFT` → verify listing struct, event emission, NFT ownership
- **Buying:** list NFT → `buyNFT` with correct value → verify NFT transferred to buyer, ETH sent to seller, listing inactive
- **Cancellation:** list NFT → `cancelListing` → verify NFT returned, listing inactive

### Edge Cases

- `listNFT` with `price = 0` reverts with `PriceCannotBeZero`
- `buyNFT` with insufficient ETH reverts with `InsufficientPayment`
- `buyNFT` on inactive listing reverts with `ListingNotActive`
- `cancelListing` by non-seller reverts with `NotSeller`
- `cancelListing` on already-cancelled listing reverts with `ListingNotActive`
- `buyNFT` on already-sold listing reverts with `ListingNotActive`
- Double-listing the same NFT (should revert since contract holds the NFT after first listing)

### Upgrade Safety Tests

- Deploy V1 → upgrade to V2 → verify V1 state is preserved
- Storage layout compatibility validation (no slot collisions)
- `reinitializer(2)` can only be called once
- V2 fee mechanism works correctly after upgrade
- V2 maxSupply enforcement works after upgrade

---

## 8. Target File Structure

```
specs/
  nft-marketplace.md          # this spec

src/
  SimpleNFT.sol
  Marketplace.sol
  SimpleNFTV2.sol
  MarketplaceV2.sol

script/
  Deploy.s.sol
  upgrades/
    ValidateUpgrade.s.sol

test/
  SimpleNFT.t.sol
  Marketplace.t.sol
  Upgrade.t.sol

foundry.toml
```
