
pragma solidity ^0.8.0;

interface ISettings {

    function maxAuctionLength() external returns (uint256);

    function minAuctionLength() external returns (uint256);

    function maxCuratorFee() external returns (uint256);

    function governanceFee() external returns (uint256);

    function minBidIncrease() external returns (uint256);

    function minVotePercentage() external returns (uint256);

    function maxReserveFactor() external returns (uint256);

    function minReserveFactor() external returns (uint256);

    function feeReceiver() external returns (address payable);

    function weth() external returns (address);

    function poolTime() external returns (uint256);

    function auctionLength() external returns (uint256);

    function preWithdrawFeeRate(uint256) external view returns (uint256);

    function copyrightTaxFee(uint8) external view returns (uint256);

    function onceUseFee(uint8) external view returns (uint256);

}