// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISecondRewarder {

    function onReward(
        address user,
        address recipient,
        uint256 amount,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        address user,
        uint256 amount
    ) external view returns (IERC20[] memory, uint256[] memory);
}
