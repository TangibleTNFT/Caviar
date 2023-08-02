// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
/* 
This version has been in use since our initial launch, and throughout this period, we have found no compelling reasons to pursue an upgrade.
From my perspective, version 0.6.12 stands out as the epitome of stability in Solidity. The majority of well-secured Solidity codes have been authored in this particular version. Given this, we believe that our current employment of this version suffices perfectly for the smart contracts associated with Caviar.
*/

interface SmartWalletChecker {
    function check(address) external view returns (bool);
}

contract SmartWalletWhitelist {
    
    mapping(address => bool) public wallets;
    address public admin;
    address public checker;
    address public future_checker;
    
    event ApproveWallet(address);
    event RevokeWallet(address);
    
    constructor(address _admin) public {
        admin = _admin;
    }
    
    function commitSetChecker(address _checker) external {
        require(msg.sender == admin, "!admin");
        future_checker = _checker;
    }

    function changeAdmin(address _admin) external {
        require(msg.sender == admin, "!admin");
        admin = _admin;
    }
    
    function applySetChecker() external {
        require(msg.sender == admin, "!admin");
        checker = future_checker;
    }
    
    function approveWallet(address _wallet) public {
        require(msg.sender == admin, "!admin");
        wallets[_wallet] = true;
        
        emit ApproveWallet(_wallet);
    }
    function revokeWallet(address _wallet) external {
        require(msg.sender == admin, "!admin");
        wallets[_wallet] = false;
        
        emit RevokeWallet(_wallet);
    }
    
    function check(address _wallet) external view returns (bool) {
        bool _check = wallets[_wallet];
        if (_check) {
            return _check;
        } else {
            if (checker != address(0)) {
                return SmartWalletChecker(checker).check(_wallet);
            }
        }
        return false;
    }
}