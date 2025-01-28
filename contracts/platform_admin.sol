// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "hardhat/console.sol";

contract PlatformAdmin {
    mapping(address => bool) public admins;
    mapping(address => mapping(address => bool)) public adminApprovals;
    mapping(address => uint256) public pendingAdminApprovalCount;
    mapping(address => uint256) public adminProposalTime;
    
      // strong (domain) => parent domain
    mapping(string => string) public parentDomains;
    // domain => DomainConfig (info about domain)
    mapping(string => DomainConfig) public domainConfigs;
    // all domains
    string[] public domainList;

    address public admin;
    uint256 public adminCount;
    uint256 public constant MIN_ADMINS = 1;
    uint256 public constant ADMIN_PROPOSAL_COOLDOWN = 1 days;

    event AdminProposed(address indexed proposer, address indexed newAdmin);
    event AdminApproved(address indexed approver, address indexed newAdmin);
    event AdminRemoved(address indexed admin);
    event DomainAdded(string domain, uint256 powerLevel);

    constructor(address _admin) {
        admins[_admin] = true;
        adminCount = 1;
    }

    function isAdmin(address _account) public view returns (bool) {
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

  
    struct DomainConfig {
        string domain;
        uint256 powerLevel;
        bool isActive;
    }

    function getDomains() external view returns (string[] memory) {
        return domainList;
    }

    function isDomainRegistered(string memory _domain) internal view returns (bool) {
        for (uint i = 0; i < domainList.length; i++) {
            if(keccak256(bytes(domainList[i])) == keccak256(bytes(_domain))) {
               return true;
            }
        }    
        return false;
    }
  
    // usage example:
    //addDomain("unitn.it", 2, "");  // Parent domain
    //addDomain("studenti.unitn.it", 1, "unitn.it");  // Subdomain
    function addDomain(string memory _domain, uint256 _powerLevel, string memory _parentDomain) public onlyAdmin {
        require(_powerLevel > 0, "Power level must be positive");
        
        require(!isDomainRegistered(_domain), "Domain already registered");
        
        domainConfigs[_domain] = DomainConfig({
            domain: _domain,
            powerLevel: _powerLevel,
            isActive: true
        });
        
        if(bytes(_parentDomain).length > 0) {
            console.log("parent domain:", _parentDomain);
            require(domainConfigs[_parentDomain].isActive, "Parent domain not registered");
            parentDomains[_domain] = _parentDomain;
        }
        domainList.push(_domain);
        emit DomainAdded(_domain, _powerLevel);
    }
    
    function canAccessDomain(string memory _userDomain, string memory _targetDomain) public view returns (bool) {
        // check trivial case first
        if (keccak256(bytes(_userDomain)) == keccak256(bytes(_targetDomain))) return true;
        // check if user domain is a subdomain of target domain
        string memory current = _userDomain;
        while(bytes(parentDomains[current]).length > 0) {
            if (keccak256(bytes(parentDomains[current])) == keccak256(bytes(_targetDomain))) {
                return true;
            }
            current = parentDomains[current];
        }
        // check the opposite case, domain is a parent domain of target domain
        current = _targetDomain;
        while(bytes(parentDomains[current]).length > 0) {
            if (keccak256(bytes(parentDomains[current])) == keccak256(bytes(_userDomain))) {
            return true;
            }
            current = parentDomains[current];
        }

        return false;
    }
}
