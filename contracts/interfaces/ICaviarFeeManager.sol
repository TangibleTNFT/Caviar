// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICaviarFeeManager {
    function distributeFees() external;
    function distributeRebaseFees(uint) external;
    function distributeEmissions(uint) external;
    function lpChef() external view returns (address);
}