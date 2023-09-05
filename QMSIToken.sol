// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OpenZeppelin/ERC20.sol";
import "./OpenZeppelin/EnumerableSet.sol";

/**
The interface for the 721 contract
These functions are required inside a market/certificate contract in order for this contract to interface correctly
*/
interface QMSI721 { 
  // all makets need to follow this interface for cross functions to work
  function tokenCommission(uint256 tokenId) external view returns (uint256);
  function tokenURI(uint256 tokenId) external view returns (string memory);
  function tokenPrice(uint256 tokenId) external view returns (uint256);
  function ownerOf(uint256 tokenId) external view returns (address);
  function tokenMinter(uint256 tokenId) external view returns (address);
  function buyToken(address from, uint256 tokenId) external;
  function trueMintingPrice() external view returns (uint256);
  function create(bytes32 dataHash, string calldata tokenURI_, uint256 tokenPrice_, uint256 commission_, address minter_) external returns (uint);
}
/**
The interface for calculating burn rate and faucet reward rate
*/
interface QMSI20 {
  function maxSupply() external view returns (uint256);
  function circulatingSupply() external view returns (uint256);
}

/**
 * @dev ERC20 spender logic
 */
abstract contract ERC20Spendable is ERC20 {
  uint256 private _burnPool;
  mapping(address => uint256) public lastClaim;
  uint256 public dailyClaimLimit; // max daily cap for faucet
  uint256 public rewardPerClaim; // negative decay reward, reset each day
  // Halving is every 4 years of activity, divides dailyClaimLimit by 2 until no more faucet
  uint256 public constant halvingInterval = 1460; // 365*4 days
  uint256 public daysConsumed; // for halving purposes
  uint256 public tokensClaimedToday; // tracks tokens claimed for the day, reset each day
  uint256 private dailyAdjuster; // keeps track of when to reset rewardPerClaim
  // Uses Euler's number constant to derive negative decay.
  // e^(-1/100) 
  uint256 private constant eN = 99004983374916819303589981151435220778399087722496;
  uint256 private constant eD = 1e50;

  // @notice Event for when the faucet is used
  event Faucet(address indexed wallet, uint256 reward);

  constructor(){
    _burnPool = 0;
    dailyClaimLimit = 3700 * 1e18; // daily tokens available to claim
    rewardPerClaim = dailyClaimLimit / 100; // 1% of daily cap per person
    daysConsumed = 0; // for tracking number of days faucet was used
    // For resetting rewards each day
    dailyAdjuster = block.timestamp;
  }
  /**
   * @dev Function to check if address is contract address
   * @param _addr The address to check
   * @return A boolean that indicates if the operation was successful
  */
  function _isContract(address _addr) internal view returns (bool) {
    uint32 size;
    assembly{
      size := extcodesize(_addr)
    }
    return (size > 0);
  }

  /**
   * @dev Function to return rate at which tokens should burn
   * @return A percent value between 0 to 100 of liquid tokens
   */
  function burnRate() external view returns (uint256) {
    return (totalSupply() * 100) / QMSI20(address(this)).maxSupply();
  }

  /**
   * @dev Function to burn tokens, but add them to a pool that others can stake to reclaim
   * @param value The amount of tokens to spend
   * @return A boolean that indicates if the operation was successful
   */
  function spend(uint256 value) public returns (bool)
  {
    _burn(msg.sender, value);
    _burnPool += value;
    return true;
  }
  /**
    * @dev Returns the amount of tokens burned that can be reclaimed through staking.
    */
  function burnPool() public view virtual returns (uint256){
      return _burnPool;
  }
 /**
   * @dev Function to subtract from the burn pool
   * @param value The tokens to take away from the pool
  */
  function _depleteBurnPool(uint256 value) internal {
    _burnPool -= value;
  }


   /**
   * @dev Function serves as equal opportunity faucet for creating new tokens for free
   * @notice each execution reduces the reward for the next (reset each day)
   * @notice each execution per msg.sender can only be done once a day
  */
  function drinkFromFaucet() external {
    // Needs to run before require checks in case tokenClaimedToday needs to be reset since it's been a day since the last reset
    // otherwise, a deadlock will occur in which tokensClaimedToday helps exceed daily allowed limit, and this will continue forever since it can't be reset in time of the check
    uint256 timeSinceDailyAdjusterRan = block.timestamp - dailyAdjuster;
    if (timeSinceDailyAdjusterRan >= 1 days) {
      // Reset tokens claimed today to 0 if it's been longer than a day, so that it's actually "tokens claimed TODAY"
      tokensClaimedToday = 0;
      daysConsumed += 1;
      // Reward per claim is reset back to original number, this value is divided by 2 per claim on a given day, so that everyone has a chance to get some value from the contract
      rewardPerClaim = dailyClaimLimit / 100;
      dailyAdjuster = block.timestamp;
    }
    
    require(canDrink(msg.sender), "QMSI-ERC20: wait 24 hours before claiming again");
    // Respect the mac supply allowed
    require( QMSI20(address(this)).circulatingSupply() + rewardPerClaim < QMSI20(address(this)).maxSupply(), "QMSI-ERC20: cannot drink above cup size"); // make sure we cannot go above max supply
    require(tokensClaimedToday + rewardPerClaim <= dailyClaimLimit, "QMSI-ERC20: Faucet has reached its daily limit");

    // make it so claim starts high daily but gets divided each time someone uses it, next day it is reset (that way everyone gets something)
    // ^ with that, we'll never hit 0 tokens to give out

    // daily claimants limit amount of participants on the network, we don't want that
    // maybe we should divide the reward on the day by 2 each time someone claims?
    // that way we NEVER hit the daily dailyClaimLimit

    lastClaim[msg.sender] = block.timestamp;

    // Transfer tokens to the claimer
    _mint(msg.sender, rewardPerClaim);
    
    emit Faucet(msg.sender, rewardPerClaim);
    // Accumulate total tokens in a given day
    tokensClaimedToday += rewardPerClaim;
    
    // Adjust the reward for the next claim
    adjustReward();
  }

 /**
   * @dev Function to check if claimer is able to drink from the faucet
   * @param claimer The address to check for eligibility
  */
  function canDrink(address claimer) public view returns (bool) {
    uint256 lastClaimedTime = lastClaim[claimer];
    if (lastClaimedTime == 0) {
        return true; // First-time claim
    }
    
    uint256 timeSinceLastClaim = block.timestamp - lastClaimedTime;
    if (timeSinceLastClaim >= 1 days) {
        return true; // Claimer can claim again after 24 hours
    }
    return false; // Claimer can't claim yet
  }

 /**
   * @dev Function (internal) for adjusting the reward using negative decay
   * @notice also handles halving events based on days of activity every 4 years of usage
  */
  function adjustReward() internal {
    // Follow Euler's negative distribution curve
    // reward = (reward) * math.exp(-k)
    rewardPerClaim = (rewardPerClaim * eN) / eD;
    // Halve the reward if needed
    if (daysConsumed >= halvingInterval) {
        dailyClaimLimit = dailyClaimLimit / 2;
        daysConsumed = 0;
    }
  }
}

contract QMSI_20 is ERC20, ERC20Spendable {
  uint256 private constant _maxSupply = 37000000 * 1e18;
  mapping (address => uint256) private _QNS;

  mapping (address => uint256) private _Staked;
  mapping (address => uint256) private _Unlocker;
  uint256 private _totalStaked;

  // @notice Event for when QNS is set
  event SetQNS(address indexed from, uint256 indexed qid);

  // @notice Event for when tokens are staked
  event Stake(address indexed from, uint256 indexed days_, uint256 indexed value_);

  // @notice Event for when tokens staked are unlocked
  event Unlock(address indexed from, uint256 indexed value_);

  // @notice Event for when cross token create occurs
  event CrossTokenBuy(address indexed from, address indexed market, address indexed to, uint256 value);

  // @notice Eveent for when cross token mint occurs
  event CrossTokenCreate(address indexed from, address indexed market, uint256 indexed mintCost);

  constructor() ERC20("Qumosi", "QMSI") {}
  /**
   * @dev Returns the max allowed supply of the token.
   */
  function maxSupply() public view virtual returns (uint256) {
      return _maxSupply;
  }

  function circulatingSupply() public view virtual returns (uint256) {
    return totalSupply() + totalStaked() + burnPool();
  }
  /**
  * @notice allows users to set the ID of their Qumosi profiles. used to verify ownership of a wallet on the website itself.
  * @param qid the Qumosi account ID (example: https://qumosi.com/members.php?id=3981987 <-- this number is the qid)
  */
  function setQNS(uint256 qid) external {
      _QNS[msg.sender] = qid;
      emit SetQNS(msg.sender, qid);
  }
  /**
    * @dev Returns Qumosi profile ID.
    */
  function getQNS(address account) public view virtual returns (uint256) {
    require(_QNS[account] > 0, "QMSI-ERC20: No QNS set");
    return _QNS[account];
  }

  /**
  * @notice stake allows users to trade time for more tokens, by reclaiming burned tokens
  * @param days_ the number of days the tokens are to be locked for
  * @param value_ the amount of tokens to lock
  */
  function stake(uint256 days_, uint256 value_) external{
    require(days_ > 0 && value_ > 0, "QMSI-ERC20: Non-zero values only");
    require(balanceOf(msg.sender) > value_, "QMSI-ERC20: Not enough tokens to lock");
    require(_Staked[msg.sender] == 0, "QMSI-ERC20: Can only stake one set of tokens at a time");
    uint256 reward = ((value_ * days_) / totalSupply());
    // require(reward + circulatingSupply() < maxSupply(), "QMSI-ERC20: Reward exceeds total supply"); // incorrect because reward is included in burnpool which is in circulation
    require(reward < burnPool(), "QMSI-ERC20: Not enough tokens to reward user from the burn pool");
    // lock both collateral and reward from burn pool
    _Staked[msg.sender] = value_ + reward;
    _Unlocker[msg.sender] = block.timestamp + (days_ * 1 days);
    _totalStaked += _Staked[msg.sender]; // includes both staking value and reward of all people
    _burn(msg.sender, value_); // does not add it to burn pool, but still removes them
    _depleteBurnPool(reward); // reclaiming burned tokens from minting 721 tokens

    // total supply is down by value staked
    // burn pool is down by reward being promised
    // total staked is up by reward and value staked
    // circulation showing no difference after conversion
    emit Stake(msg.sender, days_, value_);
  }
  /**
  * @notice allows for user to unlock tokens locked using stake function
  */
  function unlockTokens() external{
    // require(_Staked[msg.sender] + circulatingSupply() < maxSupply(), "QMSI-ERC20: Reward exceeds total supply"); // incorrect because reward is already in total staked value
    require(_Staked[msg.sender] > 0, "QMSI-ERC20: Not staking any tokens to unlock");
    require(block.timestamp > _Unlocker[msg.sender], "QMSI-ERC20: tokens are still locked");
    _mint(msg.sender, _Staked[msg.sender]); // we mint the reward and value staked from before
    _totalStaked -= _Staked[msg.sender]; // takes away reward and value staked back to owner
    emit Unlock(msg.sender, _Staked[msg.sender]);
    _Staked[msg.sender] = 0;

    // totalsupply is up by reward and value staked
    // total staked is down by reward and value staked
    // burn pool is unchanged
    // circulation showing no diference after conversion
  }
  /**
    * @dev Returns the amount staked in total in the entire smart contract.
    */
  function totalStaked() public view virtual returns (uint256) {
      return _totalStaked;
  }
  /**
    * @notice for checking the amount of locked/staked tokens of a particular user
    * @param account the address of the account that is staking an amount
    * @return The amount of tokens that are currently being staked
    */
  function lockedBalanceOf(address account) public view virtual returns (uint256) {
      return _Staked[account];
  }
  /**
    * @notice for checking the date an account is allowed to claim locked tokens
    * @param account the address of the account that is staking an amount
    * @return The date of when the tokens can be claimed back
    */
  function unlockDate(address account) public view virtual returns (uint256) {
      return _Unlocker[account];
  }
  /**
    * @notice Staking rewards estimator
    * @param days_ the number of days the tokens are to be locked for
    * @param value_ the amount of tokens to lock
    */
  function rewardsCalculator(uint256 days_, uint256 value_) public view virtual returns (uint256) {
    // should take into account total staked. if many are staked, lower the reward.
    require(value_ <= totalSupply(), "QMSI-ERC20: Value exceeds available token supply");
    // reward formula for staking
    uint256 reward = ((value_ * days_) / totalSupply());
    
    require(reward < burnPool(), "QMSI-ERC20: Not enough tokens to reward user from the burn pool");
    require(reward + circulatingSupply() < maxSupply(), "QMSI-ERC20: Reward exceeds total supply");
    return reward;
  }

  /**
   * @dev Function to buy certificate using tokens from this contract if certificate is for sale.
   * @param market the address of the certificate contract, must be a spender
   * @param to the address of who we're sending tokens to
   * @param tokenId the tokenId of the token we're buying from market
   * @param tokenPrice_ the price of the token, used so after page load it is cached in the request
   * @param tokenCommission_ the commission of the token, used so after page load it is cached in the request
   * @return A boolean that indicates if the operation was successful
  */
  function crossTokenBuy(address market, address to, uint256 tokenId, uint256 tokenPrice_, uint256 tokenCommission_) public returns (bool) {
    require(balanceOf(msg.sender) >= tokenPrice_, "QMSI-ERC20: Insufficient tokens");
    require(_isContract(market) == true, "QMSI-ERC20: Only contract addresses are considered markets.");
    // To prevent price manipulation by making user aware of the price by including it in the function call
    require(tokenPrice_ == QMSI721(market).tokenPrice(tokenId), "QMSI-ERC721: Price is not equal");
    // To prevent commission manipulation by making user aware of the rate prior to making the function call
    require(tokenCommission_ == QMSI721(market).tokenCommission(tokenId), "QMSI-ERC721: Commission rate does not match");
    require(tokenCommission_ <= 100 && tokenCommission_ >= 0, "QMSI-ERC721: Commission must be a percent");
    require(bytes(QMSI721(market).tokenURI(tokenId)).length > 0, "QMSI-ERC721: Nonexistent token");

    require(QMSI721(market).tokenPrice(tokenId) > 0, "QMSI-ERC721: Token not for sale");
    require(msg.sender != QMSI721(market).ownerOf(tokenId), "QMSI-ERC721: Cannot buy your own token");
    require(to == QMSI721(market).ownerOf(tokenId), "QMSI-ERC721: Sending tokens to the wrong owner");

    if(tokenCommission_ > 0 && msg.sender != QMSI721(market).tokenMinter(tokenId)){
      transfer(to, (tokenPrice_ * (100 - tokenCommission_)) / 100);
      transfer(QMSI721(market).tokenMinter(tokenId), (tokenPrice_ * tokenCommission_) / 100);
    }else{
      transfer(to, tokenPrice_);
    }
    QMSI721(market).buyToken(msg.sender, tokenId);
    emit CrossTokenBuy(msg.sender, market, to, tokenPrice_);
    return true;
  }

  /**
   * @dev Function to mint a certificate using tokens from this contract and the minting price of the ERC721 contract
   * @param market the address of the certificate contract
    * @param dataHash A representation of the certificate data using the Aria
    *   protocol (a 0xcert cenvention).
    * @param tokenURI_ The remote location of the certificate's JSON artifact, represented by the dataHash
    * @param tokenPrice_ The (optional) price of the certificate in token currency in order for someone to buy it and transfer ownership of it
    * @param commission_ The (optional) percentage that the original minter will take each time the certificate is bought
   * @param mintingPrice_ The price of minting a certificate (so that we know the "client" is not unaware of a burn rate change, if there is one prior to executing the create function)
   * @return A boolean that indicates if the operation was successful
  */
  function crossTokenCreate(address market, bytes32 dataHash, string calldata tokenURI_, uint256 tokenPrice_, uint256 commission_, uint256 mintingPrice_) public returns (uint) {
    // verify that user is aware of the 721 market mint price, so no manipulation can occur
    uint256 mintingPrice = QMSI721(market).trueMintingPrice();
    require(mintingPrice_ == mintingPrice, "QMSI-ERC20: Minting price does not match");
    require(tokenPrice_ <= maxSupply() && tokenPrice_ >= 0 && mintingPrice_ <= maxSupply() && mintingPrice_ >= 0, "QMSI-ERC20: Invalid units for token or minting prices");
    require(commission_ <= 100 && commission_ >= 0, "QMSI-ERC721: Commission must be a percent");
    require(bytes(tokenURI_).length > 0, "QMSI-ERC721: Must define token URI string");
    // determine value that needs to be burrned, will always be equal to or less than minting price
    uint256 burnValue = (mintingPrice*this.burnRate())/100;
    require(balanceOf(msg.sender) >= burnValue, "QMSI-ERC20: Insufficient tokens");
    spend(burnValue);
    emit CrossTokenCreate(msg.sender, market, burnValue);
    
    return QMSI721(market).create(dataHash, tokenURI_, tokenPrice_, commission_, msg.sender);

    // total supply is down by value spent
    // burn pool is up by value spent
    // total staked is unchanged
    // circulation showing no difference after conversion
  }
}