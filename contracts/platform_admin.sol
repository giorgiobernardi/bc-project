// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "hardhat/console.sol";
import "./base/BaseAdmin.sol";
import "./libraries/DomainLib.sol";

contract PlatformAdmin is BaseAdmin {
    using DomainLib for DomainLib.DomainConfig;

    mapping(string => string) public parentDomains;
    mapping(string => DomainLib.DomainConfig) public domainConfigs;
    string[] public domainList;

    uint256 public constant ADMIN_PROPOSAL_COOLDOWN = 1 days;
    mapping(address => mapping(address => bool)) public adminApprovals;
    mapping(address => uint256) public pendingAdminApprovalCount;
    mapping(address => uint256) public adminProposalTime;

    address public admin;

    uint256 public constant DOMAIN_REGISTRATION_FEE = 1 ether;
    uint256 public constant DOMAIN_RENEWAL_FEE = 0.5 ether;
    uint256 public constant REGISTRATION_DURATION = 10 days;

    event DomainExpired(string domain, uint256 expiryDate);
    event DomainRenewed(string domain, uint256 newExpirationDate);

    modifier domainNotExpired(string memory _domain) {
        require(
            domainConfigs[_domain].expiryDate > block.timestamp,
            "Domain expired"
        );
        _;
    } 

    modifier hasPaid(){
        require(msg.value >= DOMAIN_REGISTRATION_FEE, "Insufficient payment");
        require(msg.sender.balance >= msg.value, "insufficient balance");
        _;
    }

    constructor(address _admin) {
        admins[_admin] = true;
        adminCount = 1;
    }

    function renewDomain(string memory _domain) public payable hasPaid {
       require(isDomainRegistered(_domain), "Domain not registered");

        DomainLib.DomainConfig storage config = domainConfigs[_domain];
        config.expiryDate = block.timestamp + REGISTRATION_DURATION;
    }

    function withdrawFees() public onlyAdmin {
        payable(msg.sender).transfer(address(this).balance);
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

        // If majority achieved, add new admin
        if (pendingAdminApprovalCount[_proposedAdmin] > adminCount / 2) {
            admins[_proposedAdmin] = true;
            adminCount++;
            delete pendingAdminApprovalCount[_proposedAdmin];
        }
    }


    function getDomains() external view returns (string[] memory) {
        return domainList;
    }

    function isDomainRegistered(
        string memory _domain
    ) internal view returns (bool) {
        for (uint i = 0; i < domainList.length; i++) {
            if (keccak256(bytes(domainList[i])) == keccak256(bytes(_domain))) {
                return domainConfigs[_domain].expiryDate >= block.timestamp;
            }
        }
        return false;
    }


    // usage example:
    //addDomain("unitn.it", 2, "");  // Parent domain
    //addDomain("studenti.unitn.it", 1, "unitn.it");  // Subdomain
    function addDomain(
        string memory _domain,
        uint256 _powerLevel,
        string memory _parentDomain
    ) public payable hasPaid {
        require(_powerLevel > 0, "Power level must be positive");
        require(!isDomainRegistered(_domain), "Domain already registered");

        if (bytes(_parentDomain).length > 0) {
            require(
                domainConfigs[_parentDomain].expiryDate >= block.timestamp,
                "Parent domain expired"
            );
        }

        domainConfigs[_domain] = DomainLib.DomainConfig({
            domain: _domain,
            powerLevel: _powerLevel,
            expiryDate: block.timestamp + REGISTRATION_DURATION
        });

        if (bytes(_parentDomain).length > 0) {
            parentDomains[_domain] = _parentDomain;
        }
        domainList.push(_domain);
    }

    function canAccessDomain(
        string memory _userDomain,
        string memory _targetDomain
    ) public view returns (bool) {
        // function also checks expiration date of domains
        if (
            !isDomainRegistered(_userDomain) ||
            !isDomainRegistered(_targetDomain)
        ) {
            return false;
        }
        // check trivial case first
        if (keccak256(bytes(_userDomain)) == keccak256(bytes(_targetDomain)))
            return true;
        // check if user domain is a subdomain of target domain
        string memory current = _userDomain;
        while (bytes(parentDomains[current]).length > 0) {
            if (
                keccak256(bytes(parentDomains[current])) ==
                keccak256(bytes(_targetDomain))
            ) {
                return true;
            }
            current = parentDomains[current];
        }
        // check the opposite case, domain is a parent domain of target domain
        current = _targetDomain;
        while (bytes(parentDomains[current]).length > 0) {
            if (
                keccak256(bytes(parentDomains[current])) ==
                keccak256(bytes(_userDomain))
            ) {
                return true;
            }
            current = parentDomains[current];
        }
        return false;
    }
}
