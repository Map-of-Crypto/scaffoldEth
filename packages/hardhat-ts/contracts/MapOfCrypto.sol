// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";

contract MapOfCrypto is ChainlinkClient, ConfirmedOwner, KeeperCompatibleInterface {
  using Chainlink for Chainlink.Request;

  uint256 private constant ORACLE_PAYMENT = (1 * LINK_DIVISIBILITY) / 10;

  struct Purchase {
    uint256 purchaseId;
    uint256 productId;
    address merchantAddress;
    address buyerAddress;
    bool paid;
    bool accepted;
    bool expired;
    uint256 deadline;
    uint256 eth_amount;
  }

  mapping(uint256 => uint256) purchaseIdToPrice;
  mapping(address => uint256) balances;
  mapping(bytes32 => address) requestIdToBuyer;
  mapping(uint256 => string) purchaseToDeliveryId;

  mapping(uint256 => Purchase) purchases;
  uint256 purchaseCounter;

  constructor() ConfirmedOwner(msg.sender) {
    setPublicChainlinkToken();
    address _oracle;
    setChainlinkOracle(_oracle);
    // For testing lets make two products that both require payment and one that doesnt need
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

    bytes32 requestId = getDataMerchantAPI(merchantId, productId);

    // Saving the amount that user sent to contract
    balances[msg.sender] += msg.value;

    //saving the address of the buyer
    requestIdToBuyer[requestId] = msg.sender;
  }

  function acceptPurchaseRequest(uint256 purchaseId) public {
    // * ensure that the merchant accepting the request is the one for which the request was made
    // * set a deadline until which the request must be fulfilled, otherwise money is refunded (more generous deadline than before accepting)

    require(purchases[purchaseId].merchantAddress == msg.sender, "Only merchant can accept request");

    // one week for bigger deadline
    purchases[purchaseId].deadline = block.timestamp + 1 weeks;
    purchases[purchaseId].accepted = true;
  }

  function fulfillPurchaseRequest(uint256 requestId, string memory packageTrackingNumber) public {
    // * ensure that it is called by the correct merchant
    // * add the package tracking number to the request data
    // * convert the amount to be sent to the merchant now and store it in the request. this is important because we want to send the correct
    //   amount of ether _at the time of purchase in the store_ and not at the time of shipping
    // * set up chainlink keeper to call completePurchaseRequest when the tracking status is "delivered"
    // TODO lets define if we need this
    require(purchases[requestId].merchantAddress == msg.sender);
    purchaseToDeliveryId[requestId] = packageTrackingNumber;
  }

  //  API CRON CHAINLINK
  function getNeedFunding(bytes memory data) public {
    // This function will return a list of purchases that need funding
    // This list gets constructed in the external adapter
    // reads all the purchases on blockchain with accepted = true and paid  = false and compares  with deliverd API if any is delivered
    // if delivered = true and paid = false then it is added to list and is sent to this function

    uint256[] memory purchaseNeedFunding = abi.decode(data, (uint256[]));

    for (uint256 i = 0; i < purchaseNeedFunding.length; i++) {
      address buyer = purchases[purchaseNeedFunding[i]].buyerAddress;
      address merchant = purchases[purchaseNeedFunding[i]].merchantAddress;
      uint256 eth_amount = purchases[purchaseNeedFunding[i]].eth_amount;

      (bool success, ) = merchant.call{ value: eth_amount }("");
      require(success, "Withdrawal failed");
      balances[buyer] = balances[buyer] - eth_amount;
      // transfer to merchantAddress
    }
    // transfer from the balances[eth_amount]
  }

  // GET API DIRECT REQUEST Chainlink
  function getDataMerchantAPI(
    // string memory jobId,
    uint256 merchantId,
    uint256 productId
  ) public returns (bytes32) {
    // Chainlink request to datamerchant API

    string memory jobId;

    Chainlink.Request memory req = buildChainlinkRequest(stringToBytes32(jobId), address(this), this.fullfillMerchantAPI.selector);

    string memory productURL = string(abi.encodePacked("https://mapofcrypto-cdppi36oeq-uc.a.run.app/products/", toString(productId)));
    string memory merchantURL = string(abi.encodePacked("https://mapofcrypto-cdppi36oeq-uc.a.run.app/merchants/", toString(merchantId)));

    req.add("productURL", productURL);
    req.add("merchantURL", merchantURL);

    return sendOperatorRequest(req, ORACLE_PAYMENT);
  }

  function fullfillMerchantAPI(
    bytes32 _requestId,
    bytes32 _currency,
    address _merchantAddress,
    uint256 _price,
    uint256 productId
  ) public recordChainlinkFulfillment(_requestId) {
    // TODO USE  currency + price with chainlink Oracle to get amount in ETH

    uint256 eth_amount;
    uint256 buyerBalance = balances[requestIdToBuyer[_requestId]];

    require(buyerBalance >= eth_amount, "You don't have enough ether deposited in the contract");

    // save in mapping relation of request Purchase Id and its price
    uint256 purchaseId = purchaseCounter++;
    purchaseIdToPrice[purchaseId] = eth_amount;
    // we add one day for deadLine
    purchases[purchaseId] = Purchase(purchaseId, productId, _merchantAddress, requestIdToBuyer[_requestId], false, false, false, 0, block.timestamp + 1 days);
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
    // TODO CHECK ALL THE DEADLINES of all the PURCHASES IF THEY HAVE BEEN REACHED
  }

  // When the keeper register detects taht we need to do a performUpKeep
  function performUpkeep(
    bytes calldata /* performData */
  ) external override {
    // validate here for malicious keepers
    //
    // TODO make list of all the purchases that are expired

    uint256[] memory expiredPurchases;

    for (uint256 i = 0; i < expiredPurchases.length; i++) {
      address buyer = purchases[expiredPurchases[i]].buyerAddress;
      uint256 eth_amount = purchases[expiredPurchases[i]].eth_amount;

      purchases[expiredPurchases[i]].expired = true;

      (bool success, ) = buyer.call{ value: eth_amount }("");
      require(success, "Withdrawal failed.");
      balances[buyer] = balances[buyer] - eth_amount;
      // transfer to merchantAddress
    }
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
