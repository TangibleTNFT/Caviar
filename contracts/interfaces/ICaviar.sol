// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface ICaviar {
    function mint(address,uint256) external;
    function burn(address,uint256) external;
    function updateSupplyAtCurrentEpoch(uint256) external;
    function totalSupply() external view returns(uint256);
    function supplyAtCurrentEpoch() external view returns(uint256);
}