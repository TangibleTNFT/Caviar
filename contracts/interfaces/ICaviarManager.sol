// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICaviarManager {
    function disableRedeem() external;
    function getCurrentEpoch() external view returns (uint256);
}