// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


interface IAdmin {
    event AdminProposed(address indexed proposer, address indexed newAdmin);
    event AdminApproved(address indexed approver, address indexed newAdmin);
    event AdminRemoved(address indexed admin);
    event DomainAdded(string domain, uint256 powerLevel);
    
    function isAdmin(address _addr) external view returns (bool);
    function addAdmin(address _newAdmin) external;
    function removeAdmin(address _admin) external;
}