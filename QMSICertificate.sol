// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Nibbstack/nf-token.sol";
import "./Nibbstack/ownable.sol";
import "./OpenZeppelin/Strings.sol";
import {ERC20Spendable} from "./QMSIToken.sol";

/**
 * @notice A non-fungible certificate that anybody can create by spending tokens
 */

interface QMSI20 {
    function burnRate() external view returns (uint256);
}

abstract contract DeadmanSwitch is Ownable {
    address private _kin;
    uint256 private _timestamp;
    constructor() {
        _kin = msg.sender;
        _timestamp = block.timestamp;
    }
    /**
    * @notice to be used by contract owner to set a deadman switch in the event of worse case scenario
    * @param kin_ the address of the next owner of the smart contract if the owner dies
    * @param days_ number of days from current time that the owner has to check-in prior to, otherwise the kin can claim ownership
    */
    function setDeadmanSwitch(address kin_, uint256 days_) onlyOwner external returns (bool){
      require(days_ < 365, "QMSI-ERC721: Must check-in once a year");
      require(kin_ != address(0), CANNOT_TRANSFER_TO_ZERO_ADDRESS);
      _kin = kin_;
      _timestamp = block.timestamp + (days_ * 1 days);
      return true;
    }
    /**
    * @notice to be used by the next of kin to claim ownership of the smart contract if the time has expired
    * @return true on successful owner transfer
    */
    function claimSwitch() external returns (bool){
      require(msg.sender == _kin, "QMSI-ERC721: Only next of kin can claim a deadman's switch");
      require(block.timestamp > _timestamp, "QMSI-ERC721: Deadman is alive");
      emit OwnershipTransferred(owner, _kin);
      owner = _kin;
      return true;
    }
    /**
    * @notice used to see who the next owner of the smart contract will be, if the switch expires
    * @return the address of the next of kin
    */
    function getKin() public view virtual returns (address) {
        return _kin;
    }
    /**
    * @notice used to get the date that the switch expires to allow for claiming it
    * @return the timestamp for which the switch expires
    */
    function getExpiry() public view virtual returns (uint256) {
        return _timestamp;
    }
}

contract QMSI_721 is NFToken, DeadmanSwitch
{
    // @notice Event for when NFT is solf
    event SoldNFT(address indexed seller, uint256 indexed tokenId, address indexed buyer);

    /// @notice The price to create new certificates
    uint256 _mintingPrice;

    /// @notice The currency to create new certificates
    ERC20Spendable _mintingCurrency;

    /// @dev The serial number of the next certificate to create
    uint256 nextCertificateId = 1;

    mapping(uint256 => bytes32) certificateDataHashes;

    // ERC721 tokenURI standard
    mapping (uint256 => string) private _tokenURIs;

    mapping (uint256 => uint256) private _tokenPrices;

    // Mappings for commission
    mapping (uint256 => uint256) private _tokenCommission;

    mapping (uint256 => address) private _tokenMinter;

    /**
     * @notice Query the certificate hash for a token
     * @param tokenId Which certificate to query
     * @return The hash for the certificate
     */
    function hashForToken(uint256 tokenId) external view returns (bytes32) {
        return certificateDataHashes[tokenId];
    }

    /**
     * @notice The price to create certificates influenced by token circulation and max supply
     * @return The price to create certificates
     */
    function mintingPrice() external view returns (uint256) {
        uint256 _burnRate = _mintingCurrency.burnRate();
        return (_mintingPrice*_burnRate)/100;
    }

    /**
     * @notice The price to create certificates
     * @return The price to create certificates
     */
    function trueMintingPrice() external view returns (uint256) {
        return _mintingPrice;
    }

    /**
     * @notice The currency (ERC20) to create certificates
     * @return The currency (ERC20) to create certificates
     */
    function mintingCurrency() external view returns (ERC20Spendable) {
        return _mintingCurrency;
    }

    /**
     * @notice Set new price to create certificates
     * @param newMintingPrice The new price
     */
    function setMintingPrice(uint256 newMintingPrice) onlyOwner external {
        _mintingPrice = newMintingPrice;
    }

    /**
     * @notice Set new ERC20 currency to create certificates
     * @param newMintingCurrency The new currency
     */
    function setMintingCurrency(ERC20Spendable newMintingCurrency) onlyOwner external {
        _mintingCurrency = newMintingCurrency;
    }

    // Base URI
    string private _baseURIextended;

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
     * @notice used by the contract owner to set a prefix string at the beginning of all token resource locations.
     * @param baseURI_ the string that goes at the beginning of all token URI
     *
     */
    function setBaseURI(string memory baseURI_) external onlyOwner() {
        _baseURIextended = baseURI_;
    }


    /**
     * @notice used for setting the certificate artifact remote location. only be called by setTokenURI.
     * @param tokenId the id of the certificate that we want to set the remote location of
     * @param _tokenURI a string that contains the URL of the artifact's location.
     *
     */
    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(bytes(_tokenURI).length > 0, "QMSI-ERC721: token URI cannot be empty");
        _tokenURIs[tokenId] = _tokenURI;
    }

    /**
     * @notice for setting the commission rate of a certificate, called by setTokenCommissionProperty only.
     * @param tokenId the id of the certificate that we want to set the commission rate
     * @param percentage the percent token commission rate that is taken by the original minter
     *
     */
    function _setTokenCommissionProperty(uint256 tokenId, uint256 percentage) internal virtual{
        require(percentage >= 0 && percentage <= 100, "QMSI-ERC721: Commission property must be a percent integer");
        _tokenCommission[tokenId] = percentage;
    }

    /**
     * @notice for setting the commission rate of a certificate, optional. only original minter can call this.
     * @param tokenId the id of the certificate that we want to set the commission rate
     * @param percentage_ the percent token commission rate that is taken by the original minter
     *
     */
    function setTokenCommissionProperty(uint256 tokenId, uint256 percentage_) external{
        require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        require(msg.sender == _tokenMinter[tokenId], "QMSI-ERC721: Must be the original minter to set commission rate");
        require(percentage_ >= 0 && percentage_ <= 100, "QMSI-ERC721: Commission property must be a percent integer");
        _setTokenCommissionProperty(tokenId, percentage_);
    }

    /**
     * @notice used for setting the original artist/minter of the certificate. called once per tokenId.
     * @param tokenId the id of the certificate that is being minted
     *
     */
    function _setTokenMinter(uint256 tokenId, address minter) internal virtual {
        require(minter != address(0), "QMSI-ERC721: Invalid address");
        _tokenMinter[tokenId] = minter;
    }

    /**
     * @notice used for setting the price of the token. can only be called from sellToken()
     * @param tokenId the id of the certificate that we want sell
     * @param _tokenPrice the amount in token currency units that we want to sell the certificate for
     *
     */
    function _setTokenPrice(uint256 tokenId, uint256 _tokenPrice) internal virtual {
        if(_tokenPrice > 0){
            _tokenPrices[tokenId] = _tokenPrice;
        }
    }

    /**
     * @notice used for creating a listing for the certificate to be bought
     * @param tokenId the id of the certificate that we want sell
     * @param _tokenPrice the amount in token currency units that we want to sell the certificate for
     *
     */
    function sellToken(uint256 tokenId, uint256 _tokenPrice) external {
        require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        require(msg.sender == idToOwner[tokenId], "QMSI-ERC721: Must own token in order to sell");
        require(_tokenPrice > 0, "QMSI-ERC721: Must set a price to sell token for");
        _setTokenPrice(tokenId, _tokenPrice);
    }

    /**
     * @notice used for removing a listing, if the certificate is up for sale
     * @param tokenId the id of the certificate that we want to remove listing of
     *
     */
    function removeListing(uint256 tokenId) external {
        require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        require(msg.sender == idToOwner[tokenId], "QMSI-ERC721: Must own token in order to remove listing");
        require(_tokenPrices[tokenId] > 0, "QMSI-ERC721: Must be selling in order to remove listing");
        _tokenPrices[tokenId] = 0;
    }

    /**
     * @notice used for setting the certificate artifact remote location
     * @param tokenId the id of the certificate that we want to set the remote location of
     * @param tokenURI a string that contains the URL of the artifact's location.
     *
     */
    function setTokenURI(uint256 tokenId, string memory tokenURI) external {
        require(bytes(_tokenURIs[tokenId]).length > 0, "QMSI-ERC721: Nonexistent token");
        require(msg.sender == _tokenMinter[tokenId], "QMSI-ERC721: Must be the original minter to set URI");
        _setTokenURI(tokenId, tokenURI);
    }

    /**
     * @notice the price of the certificate in token currency units, if there is one
     * @param tokenId the id of the certificate that we want to the price of
     * @return the amount in token currency the token is set to sell at
     *
     */
    function tokenPrice(uint256 tokenId) external view returns (uint256) {
        return _tokenPrices[tokenId];
    }

    /**
     * @notice for finding the commission rate of a certificate, if there is one
     * @param tokenId the id of the certificate that we want to know the commission rate
     * @return the percent token commission rate that is taken by the original minter
     *
     */
    function tokenCommission(uint256 tokenId) external view returns (uint256) {
        return _tokenCommission[tokenId];
    }

    /**
     * @notice for finding who the original minter of a certificate is
     * @param tokenId the id of the certificate that we want to know the minter of
     * @return the address of the original minter of the certificate
     *
     */
    function tokenMinter(uint256 tokenId) external view returns (address) {
        return _tokenMinter[tokenId];
    }

    /**
     * @notice to be called by the buy function inside the ERC20 contract
     * @param from the address we are transferring the NFT from
     * @param tokenId the id of the NFT we are moving
     *
     */
    function buyToken(address from, uint256 tokenId) external {
        require(_isContract(msg.sender) == true, "QMSI-ERC721: Only contract addresses can use this function");
        require(msg.sender == address(_mintingCurrency), "QMSI-ERC721: Only the set currency can buy NFT on behalf of the user");
        _transfer(from, tokenId);
        _tokenPrices[tokenId] = 0;
        emit SoldNFT(idToOwner[tokenId], tokenId, from);
    }

    /**
     * @notice this string goes at the beginning of the tokenURI, if the contract owner chose to set a value for it.
     * @return a string of the base URI if there is one
     *
     */
    function baseURI() external view returns (string memory) {
        return _baseURIextended;
    }

    /**
     * @notice Purpose is to set the remote location of the JSON artifact
     * @param tokenId the id of the certificate
     * @return The remote location of the JSON artifact
     *
     */
    function tokenURI(uint256 tokenId) public view virtual returns (string memory) {
        require(bytes(_tokenURIs[tokenId]).length > 0, "ERC721Metadata: URI query for nonexistent token");

        string memory _tokenURI = _tokenURIs[tokenId];
        string memory base = _baseURIextended;

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return _tokenURI;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(_tokenURI).length > 0) {
            return string(abi.encodePacked(base, _tokenURI));
        }
        // If there is a baseURI but no tokenURI, concatenate the tokenID to the baseURI.
        return string(abi.encodePacked(base, Strings.toString(tokenId)));
    }

    /**
     * @notice Allows anybody to create a certificate, takes payment from the
     *   msg.sender. Can only be called by the mintingCurrency contract
     * @param dataHash A representation of the certificate data using the Aria
     *   protocol (a 0xcert cenvention).
     * @param tokenURI_ The (optional) remote location of the certificate's JSON artifact, represented by the dataHash
     * @param tokenPrice_ The (optional) price of the certificate in token currency in order for someone to buy it and transfer ownership of it
     * @param commission_ The (optional) percentage that the original minter will take each time the certificate is bought
     * @return The new certificate ID
     *
     */
    function create(bytes32 dataHash, string memory tokenURI_, uint256 tokenPrice_, uint256 commission_, address minter_) external returns (uint) {
        require(_isContract(msg.sender) == true, "QMSI-ERC721: Only contract addresses can use this function");
        require(msg.sender == address(_mintingCurrency), "QMSI-ERC721: Only the set currency can create NFT on behalf of the user");

        // Set URI of token
        _setTokenURI(nextCertificateId, tokenURI_);

        // Set price of token (optional)
        _setTokenPrice(nextCertificateId, tokenPrice_);

        // Set token minter (the original artist)
        _setTokenMinter(nextCertificateId, minter_);
        _setTokenCommissionProperty(nextCertificateId, commission_);

        // Create the certificate
        uint256 newCertificateId = nextCertificateId;
        _mint(minter_, newCertificateId);
        certificateDataHashes[newCertificateId] = dataHash;
        nextCertificateId = nextCertificateId + 1;

        return newCertificateId;
    }
}
