// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

contract MapOfCrypto is ChainlinkClient, ConfirmedOwner, KeeperCompatibleInterface {
  using Chainlink for Chainlink.Request;

  uint256 public monitors;

  uint256 private constant ORACLE_PAYMENT = (1 * LINK_DIVISIBILITY) / 10;

  bytes32 public currency;

  uint256 public price;

  bytes public _bytes;

  uint256[] public _list;

  bool public test;

  bytes32 public firstData;

  struct RequestedPurchase {
    bool paid;
    uint256 productId;
    bool confirmed;
  }

  bytes public needFunding;

  RequestedPurchase[] public requestedPurchaseList;

  constructor(address _oracle) ConfirmedOwner(msg.sender) {
    setPublicChainlinkToken();
    setChainlinkOracle(_oracle);
    // For testing lets make two products that both require payment and one that doesnt need

    requestedPurchaseList.push(RequestedPurchase(false, 1, true));
    requestedPurchaseList.push(RequestedPurchase(false, 2, true));
    requestedPurchaseList.push(RequestedPurchase(false, 3, false));
  }

  function returnRequestedPurchaseList() public view returns (RequestedPurchase[] memory) {
    return requestedPurchaseList;
  }

  function returnListFunding() public view returns (uint256[] memory) {
    return _list;
  }

  function makePurchaseRequest(
    uint256 merchantId,
    uint256 productId,
    string memory targetCountry
  ) public payable {
    // * get data for (merchantId, productId) from our API via Chainlink   ->  getDataMerchantAPI
    // getDataMerchantAPI(merchantId, productId);
    // * make sure that the sent amount is at least the amount required for the product including shipping to target country (using Chainlink conversion data)
    // * set a deadline for the merchant to accept the request, otherwise money is refunded
    // * save the purchaseRequest in the contract, so the merchant can accept it
  }

  function acceptPurchaseRequest(uint256 requestId) public {
    // * ensure that the merchant accepting the request is the one for which the request was made
    // * set a deadline until which the request must be fulfilled, otherwise money is refunded (more generous deadline than before accepting)
    // Set the status of requests = accepted with status delivered = false
  }

  function fulfillPurchaseRequest(uint256 requestId, string memory packageTrackingNumber) public {
    // * ensure that it is called by the correct merchant
    // * add the package tracking number to the request data
    // * convert the amount to be sent to the merchant now and store it in the request. this is important because we want to send the correct
    //   amount of ether _at the time of purchase in the store_ and not at the time of shipping
    // * set up chainlink keeper to call completePurchaseRequest when the tracking status is "delivered"
  }

  // GET API Chainlink

  function getDeliveredTransactions() public {
    // Return here a list of all the transactions that need funding (the recipient addreses that should receive money because status = delivred)
    // Chainlink request to our api

    test = true;
  }

  function fullfillDeliveredTransactions(bytes32 _requestId, bytes memory bytesResponse) public recordChainlinkFulfillment(_requestId) {
    // fetch the response data from our api
    // decode here the bytesResponse
    // check on chain for our struct of transactions with status deliverd = false and accepted
    // If api returns that delivered = true then save the list of address recipients as needs funding
    // return list()
  }

  function cronExecution(bytes memory data) public {
    needFunding = data;

    uint256[] memory list = abi.decode(data, (uint256[]));

    _list = list;
  }

  function getDataMerchantAPI(
    string memory jobId,
    uint256 merchantId,
    uint256 productId
  ) public {
    // Chainlink request to datamerchant API

    // string memory jobId = "42754ae13e534700b9ba848fc8462523";

    Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32(jobId), address(this), this.fullfillMerchantAPI.selector);

    string memory productURL = string(abi.encodePacked("https://mapofcrypto-cdppi36oeq-uc.a.run.app/products/", toString(productId)));
    // string memory merchantURL = string(abi.encodePacked("https://mapofcrypto-cdppi36oeq-uc.a.run.app/merchants/",toString(merchantId)));

    req.add("productURL", productURL);
    // req.add("merchantURL",merchantURL);

    sendOperatorRequest(req, ORACLE_PAYMENT);
  }

  function fullfillMerchantAPI(
    bytes32 _requestId,
    bytes32 _currency,
    uint256 _price
  ) public recordChainlinkFulfillment(_requestId) {
    //  decode the byetesResponse
    // make a struct with the requests on chain using the data from the API
    // fulfillPurchaseRequest()

    currency = _currency;
    price = _price;
  }

  /// Keeper functions

  function checkUpkeep(
    bytes calldata /* checkData */
  )
    external
    view
    override
    returns (
      bool upkeepNeeded,
      bytes memory /* performData */
    )
  {
    if (_list.length > 0) {
      upkeepNeeded = true;
    }
  }

  // When the keeper register detects taht we need to do a performUpKeep
  function performUpkeep(
    bytes calldata /* performData */
  ) external override {
    // validate here for malicious keepers so we will call getDeliveredTransactions again
    // return list of PurchaseRequests that need funding
    // make the transfers from our smart contract to the recipients according to the response
    // change status delivered= true in our struct
    // we will get the relationship between productId Address and fundingNeeded
    // do transfer and then change status Paid from the object
  }

  // UTILS

  function getChainlinkToken() public view returns (address) {
    return chainlinkTokenAddress();
  }

  function withdrawLink() public onlyOwner {
    LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
    require(link.transfer(msg.sender, link.balanceOf(address(this))), "Unable to transfer");
  }

  function cancelRequest(
    bytes32 _requestId,
    uint256 _payment,
    bytes4 _callbackFunctionId,
    uint256 _expiration
  ) public onlyOwner {
    cancelChainlinkRequest(_requestId, _payment, _callbackFunctionId, _expiration);
  }

  function stringToBytes32(string memory source) private pure returns (bytes32 result) {
    bytes memory tempEmptyStringTest = bytes(source);
    if (tempEmptyStringTest.length == 0) {
      return 0x0;
    }

    assembly {
      // solhint-disable-line no-inline-assembly
      result := mload(add(source, 32))
    }
  }

  function toString(uint256 value) internal pure returns (string memory) {
    // Inspired by OraclizeAPI's implementation - MIT licence
    // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

    if (value == 0) {
      return "0";
    }
    uint256 temp = value;
    uint256 digits;
    while (temp != 0) {
      digits++;
      temp /= 10;
    }
    bytes memory buffer = new bytes(digits);
    while (value != 0) {
      digits -= 1;
      buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
      value /= 10;
    }
    return string(buffer);
  }

  function bytes32ToString(bytes32 _bytes32) public pure returns (string memory) {
    uint8 i = 0;
    while (i < 32 && _bytes32[i] != 0) {
      i++;
    }
    bytes memory bytesArray = new bytes(i);
    for (i = 0; i < 32 && _bytes32[i] != 0; i++) {
      bytesArray[i] = _bytes32[i];
    }
    return string(bytesArray);
  }
}
