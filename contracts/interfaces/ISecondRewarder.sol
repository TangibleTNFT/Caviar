// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISecondRewarder {

    function onReward(
        uint256 pid,
        address user,
        address recipient,
        uint256 amount,
        uint256 newLpAmount
    ) external;

    function pendingTokens(
        uint256 pid,
        address user,
        uint256 amount
    ) external view returns (IERC20[] memory, uint256[] memory);
}
