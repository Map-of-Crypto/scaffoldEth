// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@chainlink/contracts/src/v0.8/ConfirmedOwner.sol";
import "@chainlink/contracts/src/v0.8/KeeperCompatible.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract MapOfCrypto is ChainlinkClient, ConfirmedOwner, KeeperCompatibleInterface {
  using Chainlink for Chainlink.Request;

  uint256 private constant ORACLE_PAYMENT = (1 * LINK_DIVISIBILITY) / 10;
  uint256 private constant batchSize = 20;
  string private jobId;

  struct Purchase {
    uint256 purchaseId;
    uint256 productId;
    address merchantAddress;
    address buyerAddress;
    bool accepted;
    uint256 deadline;
    uint256 ethPrice;
    uint256 ethFunded;
    string trackingNumber;
  }

  mapping(address => uint256) balances;
  mapping(bytes32 => uint256) requestToPurchase;

  mapping(uint256 => Purchase) purchases;
  uint256 purchaseCounter;
  uint256 lowestPurchaseId;

  AggregatorV3Interface internal ethUsdFeed;

  constructor(
    address _oracle,
    address _ethUsdFeed,
    string memory _jobId
  ) ConfirmedOwner(msg.sender) {
    setPublicChainlinkToken();
    setChainlinkOracle(_oracle);
    ethUsdFeed = AggregatorV3Interface(_ethUsdFeed);
    jobId = _jobId;
  }

  function makePurchaseRequest(uint256 merchantId, uint256 productId) public payable {
    // * get data for (merchantId, productId) from our API via Chainlink   ->  getDataMerchantAPI
    // getDataMerchantAPI(merchantId, productId);
    // * make sure that the sent amount is at least the amount required for the product including shipping to target country (using Chainlink conversion data)
    // * set a deadline for the merchant to accept the request, otherwise money is refunded
    // * save the purchaseRequest in the contract, so the merchant can accept it

    uint256 purchaseId = purchaseCounter++;
    Purchase storage newPurchase = purchases[purchaseId];
    newPurchase.productId = productId;
    newPurchase.buyerAddress = msg.sender;
    newPurchase.ethFunded = msg.value;

    bytes32 requestId = getDataMerchantAPI(merchantId, productId);

    requestToPurchase[requestId] = purchaseId;
  }

  function fundPurchase(uint256 purchaseId) public payable {
    require(msg.value > 0, "Cannot fund a purchase without sending coins!");
    require(purchaseExists(purchaseId), "Purchase does not exist!");
    require(purchases[purchaseId].accepted == false, "Cannot fund an accepted purchase!");
    require(!isPurchaseExpired(purchaseId), "Cannot fund an expired purchase!");
    require(purchases[purchaseId].ethFunded + msg.value <= purchases[purchaseId].ethPrice, "Cannot fund the purchase beyond the price!");

    purchases[purchaseId].ethFunded += msg.value;
    purchases[purchaseId].deadline = block.timestamp + 1 weeks;
  }

  function acceptPurchaseRequest(uint256 purchaseId) public {
    // * ensure that the merchant accepting the request is the one for which the request was made
    // * set a deadline until which the request must be fulfilled, otherwise money is refunded (more generous deadline than before accepting)

    require(purchaseExists(purchaseId), "Purchase does not exist!");
    require(purchases[purchaseId].merchantAddress == msg.sender, "Only merchant can accept request");
    require(!isPurchaseExpired(purchaseId), "Cannot accept an expired purchase!");
    require(isPurchaseFunded(purchaseId), "Cannot accept a purchase that is not funded!");

    purchases[purchaseId].accepted = true;
    purchases[purchaseId].deadline = block.timestamp + 1 weeks;
  }

  function fulfillPurchaseRequest(uint256 purchaseId, string memory packageTrackingNumber) public {
    // * ensure that it is called by the correct merchant
    // * add the package tracking number to the request data
    // * convert the amount to be sent to the merchant now and store it in the request. this is important because we want to send the correct
    //   amount of ether _at the time of purchase in the store_ and not at the time of shipping
    // * set up chainlink keeper to call completePurchaseRequest when the tracking status is "delivered"
    require(purchaseExists(purchaseId), "Purchase does not exist!");
    require(purchases[purchaseId].merchantAddress == msg.sender, "Only merchant for this purchase can supply the tracking number!");
    require(purchases[purchaseId].accepted, "Only accepted purchases can be fulfilled!");
    purchases[purchaseId].trackingNumber = packageTrackingNumber;
  }

  // TODO API CRON CHAINLINK
  // function getNeedFunding(bytes memory data) public {
  //   // This function will return a list of purchases that need funding
  //   // This list gets constructed in the external adapter
  //   // reads all the purchases on blockchain with accepted = true and paid  = false and compares  with deliverd API if any is delivered
  //   // if delivered = true and paid = false then it is added to list and is sent to this function

  //   uint256[] memory purchaseNeedFunding = abi.decode(data, (uint256[]));

  //   for (uint256 i = 0; i < purchaseNeedFunding.length; i++) {
  //     address buyer = purchases[purchaseNeedFunding[i]].buyerAddress;
  //     address merchant = purchases[purchaseNeedFunding[i]].merchantAddress;
  //     uint256 eth_amount = purchases[purchaseNeedFunding[i]].eth_amount;

  //     (bool success, ) = merchant.call{ value: eth_amount }("");
  //     require(success, "Withdrawal failed.");
  //     balances[buyer] = balances[buyer] - eth_amount;
  //     // transfer to merchantAddress
  //   }
  //   // transfer from the balances[eth_amount]
  // }

  // GET API DIRECT REQUEST Chainlink
  function getDataMerchantAPI(uint256 merchantId, uint256 productId) public returns (bytes32) {
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
    uint256 purchaseId = requestToPurchase[_requestId];
    require(purchaseExists(purchaseId), "Purchase does not exist!");

    Purchase storage purchase = purchases[purchaseId];

    purchase.merchantAddress = _merchantAddress;

    // TODO use correct price feed depending on currency
    (, int256 price, , , ) = ethUsdFeed.latestRoundData();
    uint256 ethPrice = (_price * (10**4) * (10**18)) / uint256(price);
    purchase.ethPrice = ethPrice;

    delete requestToPurchase[_requestId];
  }

  /// Keeper functions

  function checkUpkeep(
    bytes calldata /* checkData */
  ) external view override returns (bool upkeepNeeded, bytes memory performData) {
    uint256 newLowestPurchaseId;
    uint256[batchSize] memory purchasesToCheck;
    uint256 k = 0;
    for (uint256 i = lowestPurchaseId; i < purchaseCounter && k < batchSize; ++i) {
      if (purchaseExists(i)) {
        if (newLowestPurchaseId == 0) {
          newLowestPurchaseId = i;
        }
        if (purchases[i].deadline >= block.timestamp) {
          purchasesToCheck[k++] = i;
        }
      }
    }

    if (k != 0 || newLowestPurchaseId > lowestPurchaseId) {
      return (true, abi.encode(newLowestPurchaseId, purchasesToCheck, k));
    }

    return (false, abi.encode(0));
  }

  // When the keeper register detects taht we need to do a performUpKeep
  function performUpkeep(bytes calldata performData) external override {
    (uint256 newLowestPurchase, uint256[] memory purchasesToCheck, uint256 k) = abi.decode(performData, (uint256, uint256[], uint256));

    for (uint256 i = lowestPurchaseId; i < newLowestPurchase; ++i) {
      if (purchaseExists(i)) {
        newLowestPurchase = i;
        break;
      }
    }

    lowestPurchaseId = newLowestPurchase;

    for (uint256 i = 0; i < k; ++i) {
      if (isPurchaseExpired(purchasesToCheck[i])) {
        Purchase storage purchase = purchases[i];
        balances[purchase.buyerAddress] += purchase.ethFunded;

        delete purchases[i];
      }
    }
  }

  // UTILS

  /**
   * @notice Withdraws coins from the sender's internal balance
   * @param target The address to send coins to
   */
  function withdraw(address target) public {
    require(balances[msg.sender] > 0, "Cannot withdraw without a balance!");

    uint256 balanceToTransfer = balances[msg.sender];
    balances[msg.sender] = 0;
    (bool success, ) = target.call{ value: balanceToTransfer }("");

    if (!success) {
      balances[msg.sender] = balanceToTransfer;
    }
  }

  function cancelPurchase(uint256 purchaseId) public {
    require(purchaseExists(purchaseId), "Cannot cancel non-existing purchase!");
    Purchase storage purchase = purchases[purchaseId];
    if (msg.sender == purchase.buyerAddress) {
      require(purchase.accepted == false, "Cannot cancel a purchase after it has been accepted!");
    } else if (msg.sender == purchase.merchantAddress) {
      require(purchase.accepted == true, "Cannot cancel a purchase if it has not been accepted!");
    } else {
      revert("Only buyer or merchant can cancel a purchase!");
    }

    balances[purchase.buyerAddress] += purchase.ethFunded;

    delete purchases[purchaseId];
  }

  function getPurchaseList() public view returns (Purchase[] memory) {
    Purchase[] memory purchaseList = new Purchase[](purchaseCounter + 1);

    for (uint256 i = 0; i < purchaseCounter; i++) {
      purchaseList[i] = purchases[i];
    }

    return purchaseList;
  }

  receive() external payable {
    balances[msg.sender] += msg.value;
  }

  function getChainlinkToken() public view returns (address) {
    return chainlinkTokenAddress();
  }

  function purchaseExists(uint256 purchaseId) private view returns (bool) {
    return purchases[purchaseId].buyerAddress != address(0);
  }

  function isPurchaseExpired(uint256 purchaseId) private view returns (bool) {
    return purchases[purchaseId].deadline < block.timestamp;
  }

  function isPurchaseFunded(uint256 purchaseId) private view returns (bool) {
    return purchases[purchaseId].ethPrice <= purchases[purchaseId].ethFunded;
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
