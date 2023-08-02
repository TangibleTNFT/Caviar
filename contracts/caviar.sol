// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
/* 
This version has been in use since our initial launch, and throughout this period, we have found no compelling reasons to pursue an upgrade.
From my perspective, version 0.6.12 stands out as the epitome of stability in Solidity. The majority of well-secured Solidity codes have been authored in this particular version. Given this, we believe that our current employment of this version suffices perfectly for the smart contracts associated with Caviar.
*/
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract caviar is ERC20 {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    address public operator;
    address public owner;

    constructor()
        public
        ERC20(
            "CAVIAR",
            "CVR"
        )
    {
        operator = msg.sender;
        owner = msg.sender;
    }

    function setOperator(address _operator) external {
        require(msg.sender == owner, "!auth");
        operator = _operator;
    }

    function mint(address _to, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");
        _mint(_to, _amount);
    }

    function burn(address _from, uint256 _amount) external {
        require(msg.sender == operator, "!authorized");
        _burn(_from, _amount);
    }
}