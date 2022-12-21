// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./OpenZeppelin/ERC20.sol";
import "./OpenZeppelin/EnumerableSet.sol";

/**
The interface for the 721 contract
These functions are required inside a market/certificate contract in order for this contract to interface correctly
*/
interface QMSI721 {
  function tokenCommission(uint256 tokenId) external view returns (uint256);
  function tokenURI(uint256 tokenId) external view returns (string memory);
  function tokenPrice(uint256 tokenId) external view returns (uint256);
  function ownerOf(uint256 tokenId) external view returns (address);
  function tokenMinter(uint256 tokenId) external view returns (address);
  function buyToken(address from, uint256 tokenId) external;
  function trueMintingPrice() external view returns (uint256);
  function create(bytes32 dataHash, string memory tokenURI_, uint256 tokenPrice_, uint256 commission_) external returns (uint);
}
/**
The interface for calculating burnRate
*/
interface QMSI20 {
  function maxSupply() external view returns (uint256);
}

/**
 * @dev ERC20 spender logic
 */
abstract contract ERC20Spendable is ERC20 {
  uint256 private _burnPool;
  constructor(){
    _burnPool = 0;
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
   * @return A percent value between 0 to 100 of tokens in circulation
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

}

contract QMSI_20 is ERC20, ERC20Spendable {
  address _transferCurrency;

  uint256 private _maxSupply;
  mapping (address => uint256) private _QNS;

  mapping (address => uint256) private _Staked;
  mapping (address => uint256) private _Unlocker;
  uint256 private _totalStaked;
  
  constructor(uint256 maxSupply_) ERC20("Qumosi", "QMSI") {
    _maxSupply = maxSupply_;
    _mint(msg.sender, maxSupply_);
  }
  /**
   * @dev Returns the max allowed supply of the token.
   */
  function maxSupply() public view virtual returns (uint256) {
      return _maxSupply;
  }

    /**
    * @notice allows users to set the ID of their Qumosi profiles. used to verify ownership of a wallet on the website itself.
    * @param qid the Qumosi account ID (example: https://qumosi.com/members.php?id=3981987 <-- this number is the qid)
    */
    function setQNS(uint256 qid) external {
        _QNS[msg.sender] = qid;
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
      require(reward + totalSupply() + totalStaked() < maxSupply(), "QMSI-ERC20: Reward exceeds total supply");
      require(reward < burnPool(), "QMSI-ERC20: Not enough tokens to reward user from the burn pool");

      _Staked[msg.sender] = value_ + reward;
      _Unlocker[msg.sender] = block.timestamp + (days_ * 1 days);
      _totalStaked += _Staked[msg.sender];
      spend(value_);
      _depleteBurnPool(reward);
    }
    /**
    * @notice allows for user to unlock tokens locked using stake function
    */
    function unlockTokens() external{
      require(_Staked[msg.sender] > 0, "QMSI-ERC20: Not staking any tokens to unlock");
      require(block.timestamp > _Unlocker[msg.sender], "QMSI-ERC20: tokens are still locked");
      _mint(msg.sender, _Staked[msg.sender]);
      _totalStaked -= _Staked[msg.sender];
      _Staked[msg.sender] = 0;
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
      require(value_ <= totalSupply(), "QMSI-ERC20: Value exceeds available token supply");
      uint256 reward = ((value_ * days_) / totalSupply());
      require(reward < burnPool(), "QMSI-ERC20: Not enough tokens to reward user from the burn pool");
      require(reward + totalSupply() + totalStaked() < maxSupply(), "QMSI-ERC20: Reward exceeds total supply");
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
  function crossTokenCreate(address market, bytes32 dataHash, string memory tokenURI_, uint256 tokenPrice_, uint256 commission_, uint256 mintingPrice_) public returns (uint) {
    // verify that user is aware of the 721 market mint price, so no manipulation can occur
    uint256 mintingPrice = QMSI721(market).trueMintingPrice();
    require(mintingPrice_ == mintingPrice, "QMSI-ERC20: Minting price does not match");
    require(tokenPrice_ <= maxSupply() && tokenPrice_ >= 0 && mintingPrice_ <= maxSupply() && mintingPrice_ >= 0, "QMSI-ERC20: Invalid units for token or minting prices");
    require(commission_ <= 100 && commission_ >= 0, "QMSI-ERC721: Commission must be a percent");
    require(bytes(tokenURI_).length > 0, "QMSI-ERC721: Must define token URI string");
    // determine value that needs to be burrned, will always be equal to or less than minting price
    uint256 burnValue = (mintingPrice*this.burnRate())/100;
    spend(burnValue);
    
    return QMSI721(market).create(dataHash, tokenURI_, tokenPrice_, commission_);
  }
}
