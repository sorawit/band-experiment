pragma solidity 0.4.25;

contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
        address msgSender = msg.sender;
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Returns true if the caller is the current owner.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Oracle {
  enum QueryStatus { INVALID, OK, NOT_AVAILABLE, DISAGREEMENT }

  function query(bytes input)
    external payable returns (bytes32 output, uint256 updatedAt, QueryStatus status);

  function queryPrice() external view returns (uint256);
}

library BandLib {
  function querySpotPrice(Oracle oracle, string memory key) internal returns(uint256) {
    (bytes32 output, , Oracle.QueryStatus status) = oracle.query.value(oracle.queryPrice())(abi.encodePacked('SPOTPX/',key));
    require(status == Oracle.QueryStatus.OK, 'DATA_UNAVAILABLE');
    return uint256(output);
  }

  function querySpotPriceWithExpiry(Oracle oracle, string memory key, uint256 timeLimit) internal returns (uint256) {
    (bytes32 output, uint256 lastUpdated, Oracle.QueryStatus status) = oracle.query.value(oracle.queryPrice())(abi.encodePacked('SPOTPX/',key));
    require(status == Oracle.QueryStatus.OK, 'DATA_UNAVAILABLE');
    require(now - lastUpdated <= timeLimit, 'DATA_OUTDATED');
    return uint256(output);
  }

  function queryScore(Oracle oracle, string memory key) internal returns (uint8, uint8) {
    (bytes32 output, , Oracle.QueryStatus status) = oracle.query.value(oracle.queryPrice())(abi.encodePacked(key));
    require(status == Oracle.QueryStatus.OK, 'DATA_NOT_READY');
    return (uint8(output[0]), uint8(output[1]));
  }

  function queryScoreWithStatus(Oracle oracle, string memory key) internal returns (uint8, uint8, Oracle.QueryStatus) {
    (bytes32 output, , Oracle.QueryStatus status) = oracle.query.value(oracle.queryPrice())(abi.encodePacked(key));
    if (status == Oracle.QueryStatus.OK)
      return (uint8(output[0]), uint8(output[1]), Oracle.QueryStatus.OK);
    return (0, 0, status);
  }

  function queryLottery(Oracle oracle, string memory key) internal returns(uint8[7] memory) {
    (bytes32 output, , Oracle.QueryStatus status) = oracle.query.value(oracle.queryPrice())(abi.encodePacked(key));
    require(status == Oracle.QueryStatus.OK, 'DATA_NOT_READY');
    return getLotteryResult(output);
  }

  function queryLotteryWithStatus(Oracle oracle, string memory key)
    internal
    returns(uint8[7] memory, Oracle.QueryStatus)
  {
    (bytes32 output, , Oracle.QueryStatus status) = oracle.query.value(oracle.queryPrice())(abi.encodePacked(key));
    if (status == Oracle.QueryStatus.OK)
      return (getLotteryResult(output), Oracle.QueryStatus.OK);
    uint8[7] memory zero;
    return (zero,status);
  }

  function getLotteryResult(bytes32 output) internal pure returns(uint8[7] memory) {
    uint8[7] memory result;
    for (uint8 i = 0; i < 7; ++i) {
      result[i] = uint8(output[i]);
    }
    return result;
  }

  /*
    Using for gas station contract for now
  */
  function queryUint256(Oracle oracle, bytes memory key) internal returns(uint256) {
    (bytes32 output, , Oracle.QueryStatus status) = oracle.query.value(oracle.queryPrice())(key);
    require(status == Oracle.QueryStatus.OK, 'DATA_UNAVAILABLE');
    return uint256(output);
  }

  function queryRaw(Oracle oracle, bytes memory key) internal returns(bytes32, uint256, Oracle.QueryStatus) {
    return oracle.query.value(oracle.queryPrice())(key);
  }
}

contract usingBandProtocol {
  using BandLib for Oracle;

  Oracle internal constant FINANCIAL = Oracle(0xa24dF0420dE1f3b8d740A52AAEB9d55d6D64478e);
  Oracle internal constant LOTTERY = Oracle(0x7b09c1255b27fCcFf18ecC0B357ac5fFf5f5cb31);
  Oracle internal constant SPORT = Oracle(0xF904Db9817E4303c77e1Df49722509a0d7266934);
  Oracle internal constant API = Oracle(0x7f525974d824a6C4Efd54b9E7CB268eBEFc94aD8);
}

interface _ExchangeRates {
    function updateRates(bytes32[] currencyKeys, uint[] newRates, uint timeSent)
        external returns(bool);
}

contract BandOracleProxy is usingBandProtocol, Ownable {
    // all keys in syn
    // "iBNB","iBTC","iCEX","iETH","iMKR","iTRX","iXTZ","sAUD","sBNB","sBTC","sCEX","sCHF","sETH","sEUR","sGBP","sJPY","sMKR","sTRX","sUSD","sXAG","sXAU","sXTZ"
    bytes32[] public keys;
    _ExchangeRates public synExchangeContract;
    Oracle public oracle;

    constructor(_ExchangeRates _synExchangeContract, Oracle _oracle) public {
        synExchangeContract = _synExchangeContract;
        oracle = _oracle;
    }

    function setKeys(bytes32[] memory _keys) public onlyOwner {
        keys.length = 0;
        for (uint256 i = 0; i < _keys.length; i++) {
            keys.push(_keys[i]);
        }
    }

    function update(bytes32 key) public payable {
        uint256 value = oracle.querySpotPrice(string(abi.encodePacked(key)));
        bytes32[] memory ks = new bytes32[](1);
        uint256[] memory vs =  new uint256[](1);
        ks[0] = key;
        vs[0] = value;
        synExchangeContract.updateRates(ks, vs, now);
    }
}