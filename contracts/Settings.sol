pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../Interfaces/ISettings.sol";
import "./SafeMath.sol";

contract Settings is Ownable, ISettings {
    using SafeMath for uint256;

    //copyright tax info
    mapping(uint8 => uint256) public copyrightTax;

    //use fee info
    mapping(uint8 => uint256) public useFee;

    /// @notice the maximum auction length
    uint256 public override maxAuctionLength;

    /// @notice the longest an auction can ever be
    uint256 public constant maxMaxAuctionLength = 8 weeks;

    /// @notice the minimum auction length
    uint256 public override minAuctionLength;

    /// @notice the shortest an auction can ever be
    uint256 public constant minMinAuctionLength = 1 days;

    uint256 public override auctionLength = 7 days;

    /// @notice governance fee max
    uint256 public override governanceFee;

    /// @notice 10% fee is max
    uint256 public constant maxGovFee = 100;

    /// @notice max curator fee
    uint256 public override maxCuratorFee;

    /// @notice the % bid increase required for a new bid
    uint256 public override minBidIncrease;

    /// @notice 10% bid increase is max
    uint256 public constant maxMinBidIncrease = 100;

    /// @notice 1% bid increase is min
    uint256 public constant minMinBidIncrease = 10;

    /// @notice the % of tokens required to be voting for an auction to start
    uint256 public override minVotePercentage;

    /// @notice the max % increase over the initial
    uint256 public override maxReserveFactor;

    /// @notice the max % decrease from the initial
    uint256 public override minReserveFactor;

    /// @notice the max % decrease from the initial
    address public override weth;

    /// @notice the address who receives auction fees
    address payable public override feeReceiver;

    uint256 public override poolTime;

    event UpdateMaxAuctionLength(uint256 _old, uint256 _new);

    event UpdateMinAuctionLength(uint256 _old, uint256 _new);

    event UpdateGovernanceFee(uint256 _old, uint256 _new);

    event UpdateCuratorFee(uint256 _old, uint256 _new);

    event UpdateMinBidIncrease(uint256 _old, uint256 _new);

    event UpdateMinVotePercentage(uint256 _old, uint256 _new);

    event UpdateMaxReserveFactor(uint256 _old, uint256 _new);

    event UpdateMinReserveFactor(uint256 _old, uint256 _new);

    event UpdateFeeReceiver(address _old, address _new);

    event UpdatePoolTime(uint256 _old, uint256 _new);

    constructor() {
        maxAuctionLength = 2 weeks;
        minAuctionLength = 3 days;
        feeReceiver = payable(msg.sender);
        minReserveFactor = 200;
        // 20%
        maxReserveFactor = 5000;
        // 500%
        minBidIncrease = 50;
        // 5%
        maxCuratorFee = 100;
        minVotePercentage = 250;
        // 25%
        copyrightTax[2] = 5;
        copyrightTax[3] = 10;
        copyrightTax[4] = 20;
        copyrightTax[5] = 30;
        useFee[2] = 75;
        useFee[3] = 150;
        useFee[4] = 250;
        useFee[5] = 350;
        weth = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
        poolTime = 30 days;
    }

    function setMaxAuctionLength(uint256 _length) external onlyOwner {
        require(_length <= maxMaxAuctionLength, "max auction length too high");
        require(_length > minAuctionLength, "max auction length too low");

        emit UpdateMaxAuctionLength(maxAuctionLength, _length);

        maxAuctionLength = _length;
    }

    function setMinAuctionLength(uint256 _length) external onlyOwner {
        require(_length >= minMinAuctionLength, "min auction length too low");
        require(_length < maxAuctionLength, "min auction length too high");

        emit UpdateMinAuctionLength(minAuctionLength, _length);

        minAuctionLength = _length;
    }

    function setGovernanceFee(uint256 _fee) external onlyOwner {
        require(_fee <= maxGovFee, "fee too high");

        emit UpdateGovernanceFee(governanceFee, _fee);

        governanceFee = _fee;
    }

    function setMaxCuratorFee(uint256 _fee) external onlyOwner {
        emit UpdateCuratorFee(governanceFee, _fee);

        maxCuratorFee = _fee;
    }

    function setMinBidIncrease(uint256 _min) external onlyOwner {
        require(_min <= maxMinBidIncrease, "min bid increase too high");
        require(_min >= minMinBidIncrease, "min bid increase too low");

        emit UpdateMinBidIncrease(minBidIncrease, _min);

        minBidIncrease = _min;
    }

    function setMinVotePercentage(uint256 _min) external onlyOwner {
        // 1000 is 100%
        require(_min <= 1000, "min vote percentage too high");

        emit UpdateMinVotePercentage(minVotePercentage, _min);

        minVotePercentage = _min;
    }

    function setMaxReserveFactor(uint256 _factor) external onlyOwner {
        require(_factor > minReserveFactor, "max reserve factor too low");

        emit UpdateMaxReserveFactor(maxReserveFactor, _factor);

        maxReserveFactor = _factor;
    }

    function setMinReserveFactor(uint256 _factor) external onlyOwner {
        require(_factor < maxReserveFactor, "min reserve factor too high");
        emit UpdateMinReserveFactor(minReserveFactor, _factor);
        minReserveFactor = _factor;
    }

    function setFeeReceiver(address payable _receiver) external onlyOwner {
        require(_receiver != address(0), "fees cannot go to 0 address");
        emit UpdateFeeReceiver(feeReceiver, _receiver);
        feeReceiver = _receiver;
    }

    function setPoolTime(uint256 _poolTime) external onlyOwner {
        emit UpdatePoolTime(poolTime, _poolTime);
        poolTime = _poolTime;
    }

    function preWithdrawFeeRate(uint256 diffTime) external override view returns (uint256) {
        uint256 rate = diffTime.mul(30).div(poolTime);
        if (rate < 10) {
            return 100;
        } else if (rate < 15) {
            return 80;
        } else if (rate < 20) {
            return 70;
        } else if (rate < 25) {
            return 60;
        } else if (rate < 30) {
            return 50;
        }
        return 0;
    }

    function copyrightTaxFee(uint8 level) external override view returns (uint256){
        return copyrightTax[level];
    }

    function onceUseFee(uint8 level) external override view returns (uint256){
        return useFee[level];
    }

}
