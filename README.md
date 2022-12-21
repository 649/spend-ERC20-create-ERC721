# Spend ERC-20 Create ERC-721 (QMSI Fork)

This is a fork of @fulldecent's https://fulldecent.github.io/spend-ERC20-create-ERC721/

This smart contract is what powers https://qumosi.com/


The following are promises this ERC20 smart contract aims to accomplish:
1. Contract owner deploys QMSI-ERC20 contract with immutable max supply
2. Users are able to mint ERC721 certificates using QMSI-ERC20 interface on any QMSI-ERC721
3. Users are able to buy ERC721 certificates using QMSI-ERC20 interface on any QMSI-ERC721
4. Users are able to burn their own QMSI-ERC20 tokens
5. Users are able to lock their own QMSI-ERC20 tokens to reclaim burned tokens by trading time
6. Users are able to set allowances and transfer tokens
7. Users are able to link their Qumosi.com profile

The following are promises this ERC721 smart contract aims to accomplish:
1. Contract owner deploys QMSI-ERC721 contract with ability to set cost of minting certificate
2. Contract owner can bridge many ERC721 smart contracts to single QMSI-ERC20 implementation
3. Contract owner may use a "deadman switch" to protect owner role in case of untimely demise
4. Contract owner may set a token URI prefix to all resource links
5. Certificate minting cost is influenced by burn rate based on tokens in circulation and max supply
6. All certificates come with verifiable checksum representing JSON preferred resource
7. All certificates come with a unique token id that increments by 1 each time the `create` function is called successfully
8. Minters are required to set a resource link on ERC721 certificate (token URI)
9. Minters are able to set commission rate on ERC721 certificate (percent integer)
10. Certificate owners are able to sell QMSI-721 for corresponding QMSI-ERC20 tokens 
11. Certificate owners are able to approveAll QMSI-ERC721 certificates to another user
12. Certificate owners and approved users are able to transfer QMSI-ERC721 certificates
13. Certificate owners and approved users are able to remove sell listings on QMSI-ERC721 certificates


## Try the beta

### Using testnet
The following contract addresses can be found on the Goerli testnet
* QMSI-ERC20: 0x2A69802F38ce178D484932AdECA92F73a414C186
* QMSI-ERC721: 0x94F70B0f70FD8C6c24E00F8ca6001a28C9aE5987

### Using our site
Install MetaMask and visit https://qumosi.com/about.php to request an invite key

Once you have an invite key, register an account at https://qumosi.com/register.php 
Switch Metamask network to Goerli testnet and make sure to have some testnet ETH to cover gas fees
We have a preconfigured Uniswap liquidity pool that can be used to trade testnet ETH for testnet QMSI

You can use your testnet QMSI ERC20 tokens to mint new projects on https://qumosi.com while also being able to sponsor other projects

## How does it work

**ERC-721 certificate contract** — This is a standard ERC-721 contract implemented using the [0xcert template](https://github.com/0xcert/ethereum-erc721/tree/master/contracts/tokens) with additional functions:

* `create(bytes32 dataHash) returns (uint256)` — Allows anybody to create a certificate (NFT). Causes the side effect of deducting a certain amount of money from the user, payable in ERC-20 tokens. The return value is a serial number. It is called by the ERC20 contract only.
* `hashForToken(uint256 tokenId) view` — Allows anybody to find the data hash for a given serial number.
* `mintingPrice() view` — Returns the mint price influenced by the burn rate.
* `trueMintingPrice() view` — Returns the mint price without influence.
* `mintingCurrency() view` — Returns the currency (ERC-20)

* `setMintingPrice(uint256)` — Allows owner (see [0xcert ownable contract](https://github.com/0xcert/ethereum-utils/blob/master/contracts/ownership/Ownable.sol)) to set price that is later influenced by the burn rate
* `setMintingCurrency(ERC20 contract)`  — Allows owner (see [0xcert ownable contract](https://github.com/0xcert/ethereum-utils/blob/master/contracts/ownership/Ownable.sol)) to set currency
* `setBaseURI(string memory baseURI_)` — Allows the contract owner to set a prefix URI on all resource links. Implemented using [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2511/files)
* `setTokenURI(uint256 tokenId, string memory tokenURI)` — Allows minter to set token URI resource link to JSON artifact. Implemented using [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2511/files)
* `setTokenCommissionProperty(uint256 tokenId, uint256 percentage_)` — Allows minter to take percentage of proceeds from SoldNFT events

* `setDeadmanSwitch(address kin_, uint256 days_)` — Allows the contract owner to set ownership to transfer to a "kin" address if the number of specified days surpass without this function being called again, in order to reset the timer.
* `claimSwitch()` — Allows the `kin` of the switch to claim it, transferring ownership. Only works if the switch is expired from the time it was set. If switch expires, owner is assumed dead.
* `getKin() view` — Returns the address of the next of kin
* `getExpiry() view` — Returns the expiration timestamp of the switch that allows ownership transfer

* `buyToken(address from, uint256 tokenId)` — Allows transferring ownership of certificate if tokens have been transferred to the owner that made the sell token listing
* `sellToken(uint256 tokenId, uint256 _tokenPrice)` — Allows the certificate owner to sell token by specifying the price in ERC20 units and token id
* `removeListing(uint256 tokenId)` — Allows the certificate owner to remove an existing listing to sell the token by specifying the token id

* `tokenPrice(uint256 tokenId) view` — Returns the price of a certificate, if it is listed for sale
* `tokenMinter(uint256 tokenId) view` — Returns the original minter of a certificate
* `tokenURI(uint256 tokenId) view` — Returns the resource link to the token's (JSON) artifact. Implemented using [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts/pull/2511/files)
* `tokenCommission(uint256 tokenId) view` — Returns the percent token commission rate that is taken by the original minter per SoldNFT event

**ERC-20 token contract** — This is a standard ERC-721 contract implemented using the [OpenZeppelin template](https://github.com/OpenZeppelin/openzeppelin-solidity/tree/master/contracts/token/ERC20) with additional functions:

* `spend(account from, uint256 value)` — Allows end user to burn their own tokens. It can only be triggered by the user, and is used in minting new certificates.
* `burnPool() view` — Returns the amount of tokens that can be reclaimed through staking. Using the `spend` function increments this pool
* `burnRate() view` — Returns a number 0 to 100 that represents the percentage of tokens in circulation (current supply / max supply)

* `stake(uint256 days_, uint256 value_)` — Allows locking ERC20 tokens for number of days to reclaim some burned tokens as reward
* `unlockTokens()` — Allows unlocking locked ERC20 tokens and reward after the unlock date has reached
* `totalStaked() view` — Returns total number of staked ERC20 tokens
* `lockedBalanceOf(address account) view` — Returns the locked balance of an address that is staking
* `unlockDate(address account) view` — Returns the unlock date for an address that is staking
* `rewardsCalculator(uint256 days_, uint256 value_) view` — Helps estimate proposed reward given by the system

* `crossTokenBuy(address market, address to, uint256 tokenId, uint256 tokenPrice_, uint256 tokenCommission_)` — Allows end user to buy ERC721 certificates that have a listing from any QMSI-721 implementation
* `crossTokenCreate(address market, bytes32 dataHash, string memory tokenURI_, uint256 tokenPrice_, uint256 commission_, uint256 mintingPrice_)` — Allows end user to create ERC721 certificates on any QMSI-721 implementation while enforcing burn rate ontop of minting cost

* `setQNS(uint256 qid)` — Allows end user to set their Qumosi profile ID on the associated wallet
* `getQNS(address account) view` — Returns Qumosi profile ID associated with wallet address

## Contract differences and assumptions
The following are key differenes in the smart contract implementation from the original.
* The ERC20 implementation does not use a spender role on corresponding ERC721 contract, it was removed in favor of not allowing the ERC721 implementation the ability to spend any user's tokens
* The users of the ERC20 implementation have the ability to burn their own tokens, it was done this way in favor of giving the user control and not the smart contract itself
* There is no owner role in this ERC20 implementation
* Inside the ERC721 implementation, there is a deadman switch to protect the owner role
* It is assumed that the burn and stake functions will self sustain token supply since no liquidity is lost, only state changed
* There is no mint capability other than the one used during the contract deployment, inside the constructor
* The "rice and chessboard" problem in staking is fixed by allowing rewards to come from burned tokens only

## How to deploy
Clone this repository and use remix to deploy both .sol source files. 

## Attribution

The original https://fulldecent.github.io/spend-ERC20-create-ERC721/ was created by William Entriken. Please visit that repository for more information.

New additions to the smart contract done by https://twitter.com/037 (@649)
