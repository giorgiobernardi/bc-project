// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract PlatformAdmin {
    mapping(address => bool) public admins;
    mapping(address => mapping(address => bool)) public adminApprovals;
    mapping(address => uint256) public pendingAdminApprovalCount;
    mapping(address => uint256) public adminProposalTime;

    address public admin;
    uint256 public adminCount;
    uint256 public constant MIN_ADMINS = 1;
    uint256 public constant ADMIN_PROPOSAL_COOLDOWN = 1 days;

    event AdminProposed(address indexed proposer, address indexed newAdmin);
    event AdminApproved(address indexed approver, address indexed newAdmin);
    event AdminRemoved(address indexed admin);

    constructor() {
        admins[msg.sender] = true;
        adminCount = 1;
    }

    function isAdmin(address _account) external view returns (bool) {
        return admins[_account];
    }

    modifier onlyAdmin() {
        require(admins[msg.sender], "Only admin can call this function");
        _;
    }

    function proposeNewAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "Invalid address");
        require(!admins[_newAdmin], "Already an admin");
        require(
            block.timestamp >=
                adminProposalTime[_newAdmin] + ADMIN_PROPOSAL_COOLDOWN,
            "Cooldown period"
        );

        adminProposalTime[_newAdmin] = block.timestamp;
        pendingAdminApprovalCount[_newAdmin] = 0;

        // Reset previous approvals
        for (uint i = 0; i < adminCount; i++) {
            adminApprovals[msg.sender][_newAdmin] = false;
        }

        emit AdminProposed(msg.sender, _newAdmin);
    }

    function approveNewAdmin(address _proposedAdmin) external onlyAdmin {
        require(
            !adminApprovals[msg.sender][_proposedAdmin],
            "Already approved"
        );
        require(adminProposalTime[_proposedAdmin] > 0, "Not proposed");

        adminApprovals[msg.sender][_proposedAdmin] = true;
        pendingAdminApprovalCount[_proposedAdmin]++;

        emit AdminApproved(msg.sender, _proposedAdmin);

        // If majority achieved, add new admin
        if (pendingAdminApprovalCount[_proposedAdmin] > adminCount / 2) {
            admins[_proposedAdmin] = true;
            adminCount++;
            delete pendingAdminApprovalCount[_proposedAdmin];
        }
    }

    function removeAdmin(address _admin) external onlyAdmin {
        require(admins[_admin], "Not an admin");
        require(adminCount > MIN_ADMINS, "Cannot remove last admin");
        require(_admin != msg.sender, "Cannot remove self");

        admins[_admin] = false;
        adminCount--;

        emit AdminRemoved(_admin);
    }
}
