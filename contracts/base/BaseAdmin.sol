// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import "../interfaces/IAdmin.sol";

abstract contract BaseAdmin is IAdmin {
    mapping(address => bool) public admins;
    uint256 public adminCount;
    uint256 public constant MIN_ADMINS = 1;
    
    modifier onlyAdmin() {
        require(admins[msg.sender], "Not admin");
        _;
    }
    
    function isAdmin(address _addr) public view returns (bool) {
        return admins[_addr];
    }

    function removeAdmin(address _admin) external onlyAdmin {
        require(admins[_admin], "Not an admin");
        require(adminCount > MIN_ADMINS, "Cannot remove last admin");
        require(_admin != msg.sender, "Cannot remove self");

        admins[_admin] = false;
        adminCount--;

        emit AdminRemoved(_admin);
    }
    function addAdmin(address _newAdmin) external onlyAdmin {}
}