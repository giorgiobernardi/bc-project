// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import "./libraries/DomainLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "hardhat/console.sol";

contract PlatformAdmin is Ownable, ReentrancyGuard {
    using DomainLib for DomainLib.DomainConfig;

    string[] public domainList;
    address public admin;
    uint256 public constant DOMAIN_REGISTRATION_FEE = 1 ether;
    uint256 public constant DOMAIN_RENEWAL_FEE = 0.5 ether;
    uint256 public constant REGISTRATION_DURATION = 10 days;

    mapping(string => string) public parentDomains;
    mapping(string => DomainLib.DomainConfig) public domainConfigs;


    event DomainExpired(string domain, uint256 expiryDate);
    event DomainRenewed(string domain, uint256 newExpirationDate);
    event FeesWithdrawn(address indexed owner, uint256 amount);


    constructor(address _admin, address _owner) Ownable(_owner) {
        admin = _admin;
    }


    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this operation");
        _;
    }

    modifier domainNotExpired(string memory _domain) {
        require(
            domainConfigs[_domain].expiryDate > block.timestamp,
            "Domain expired"
        );
        _;
    } 

    function isOwner() public view returns (bool) {
        return msg.sender == owner();
    }

    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

    modifier hasPaid(){
        require(msg.value >= DOMAIN_REGISTRATION_FEE, "Insufficient payment");
        require(msg.sender.balance >= msg.value, "insufficient balance");
        _;
    }

    function setAdmin(address _admin) public onlyOwner {
        admin = _admin;
    }

    function renewDomain(string calldata _domain) public payable hasPaid{
        console.log("exp date:",domainConfigs[_domain].expiryDate);
        require(hasDomainExpired(_domain), "Domain not expired");

        DomainLib.DomainConfig storage config = domainConfigs[_domain];
        config.expiryDate = block.timestamp + REGISTRATION_DURATION;
    }

    function withdrawFees() public onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(msg.sender).call{value: balance}("");
        require(success, "Transfer failed");
        
        emit FeesWithdrawn(msg.sender, balance);
    }

    function getDomains() external view returns (string[] memory) {
        console.log("Getting domainList");
        return domainList;
    }

    function hasDomainExpired(string calldata _domain) public view returns (bool) {
        return (domainConfigs[_domain].expiryDate < block.timestamp && 
            domainConfigs[_domain].expiryDate > 0);
    }

    function isDomainRegistered(
        string memory _domain
    ) internal view returns (bool) {
        for (uint i = 0; i < domainList.length; i++) {
            if (keccak256(bytes(domainList[i])) == keccak256(bytes(_domain))) { 
                return domainConfigs[_domain].expiryDate > block.timestamp;
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
        console.log("Domain expiry: ", domainConfigs[_domain].expiryDate);
        console.log("Domain added: ", _domain);
        
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
