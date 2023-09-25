// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IPearlGauge {
  function rewards() external view returns(uint256 reward);
  function getReward() external;
  function earned(address account) external view returns (uint256 reward);
  function deposit(uint256 _amount) external;
  function withdraw(uint256 _amount) external;
  function balanceOf(address _account) external view returns (uint256);
}