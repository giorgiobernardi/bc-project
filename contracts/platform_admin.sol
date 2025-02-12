// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./libraries/DomainLib.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PlatformAdmin is Ownable, ReentrancyGuard {
    using DomainLib for DomainLib.DomainConfig;

    // Contract state
    bool public paused;
    // List of registered domains
    string[] public domainList;
    // Admin address
    address public admin;
    uint256 public constant DOMAIN_REGISTRATION_FEE = 1 ether;
    uint256 public constant DOMAIN_RENEWAL_FEE = 0.5 ether;
    uint256 public constant REGISTRATION_DURATION = 10 days;

    // Mapping of domain to parent domain. Depending on the domain hierarchy, a voter can vote on it and all its subdomains
    mapping(string => string) public parentDomains;

    // Mapping of domain to its configuration
    mapping(string => DomainLib.DomainConfig) public domainConfigs;

    event DomainExpired(string domain, uint256 expiryDate);
    event DomainRenewed(string domain, uint256 newExpirationDate);
    event FeesWithdrawn(address indexed owner, uint256 amount);

    /**
     * Constructor for the PlatformAdmin contract
     * @param _admin The address of the backend
     * @param _owner The address of the owner
     */
    constructor(address _admin, address _owner) Ownable(_owner) {
        admin = _admin;
        paused = false;
    }

    /**
     * Modifier to check if the contract is paused
     */
    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    /**
     * Pause the contract, virtually stopping all operations
     */
    function pause() external onlyOwner {
        paused = true;
    }

    /**
     * Unpause the contract, resuming all operations
     */
    function unpause() external onlyOwner {
        paused = false;
    }

    /**
     * Modifier to check if the caller is the admin. Only the backend can perform register proposals on behalf of its users
     */
    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this operation");
        _;
    }

    /**
     * Modifier to check if the domain has not expired. Proposals can only be made on active domains
     */
    modifier domainNotExpired(string memory _domain) {
        require(
            domainConfigs[_domain].expiryDate > block.timestamp,
            "Domain expired"
        );
        _;
    }

    /**
     * Modifier to check if the caller is the owner
     */
    function isOwner() public view returns (bool) {
        return msg.sender == owner();
    }

    /**
     * Get the balance of the contract
     */
    function getContractBalance() public view returns (uint) {
        return address(this).balance;
    }

    /**
     * Modifier to check if the caller has paid the registration fee
     */
    modifier hasPaid() {
        require(msg.value >= DOMAIN_REGISTRATION_FEE, "Insufficient payment");
        require(msg.sender.balance >= msg.value, "insufficient balance");
        _;
    }

    /**
     * Defines a new backend implementation for the contract with a new private key
     * @param _admin The address of the new admin
     */
    function setAdmin(address _admin) public whenNotPaused onlyOwner {
        admin = _admin;
    }

    /**
     * Renews a domain that has expired by extending its expiry date after a successful payment
     * @param _domain The domain to be renewed
     */
    function renewDomain(
        string calldata _domain
    ) public payable whenNotPaused hasPaid {
        require(hasDomainExpired(_domain), "Domain not expired");

        DomainLib.DomainConfig storage config = domainConfigs[_domain];
        config.expiryDate = block.timestamp + REGISTRATION_DURATION;
    }

    /**
     * Withdraw fees from the contract
     */
    function withdrawFees() public onlyOwner whenNotPaused nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");

        (bool success, ) = payable(msg.sender).call{value: balance}("");
        require(success, "Transfer failed");

        emit FeesWithdrawn(msg.sender, balance);
    }

    /**
     * Get the list of registered domains in the contract
     */
    function getDomains()
        external
        view
        whenNotPaused
        returns (string[] memory)
    {
        return domainList;
    }

    /**
     * Check if a domain has expired
     * @param _domain The domain to check
     */
    function hasDomainExpired(
        string calldata _domain
    ) public view whenNotPaused returns (bool) {
        return (domainConfigs[_domain].expiryDate < block.timestamp &&
            domainConfigs[_domain].expiryDate > 0);
    }

    /**
     * Check if a domain is registered
     * @param _domain The domain to check
     */
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

    /**
     *
     * @param _domain The domain to register
     * @param _powerLevel The power level of the users registered with that domain
     * @param _parentDomain The parent domain of the domain to register
     * usage example:
     * addDomain("unitn.it", 2, "");  // Parent domain
     * addDomain("studenti.unitn.it", 1, "unitn.it");  // Subdomain
     */
    function addDomain(
        string memory _domain,
        uint128 _powerLevel,
        string memory _parentDomain
    ) public payable whenNotPaused hasPaid {
        require(bytes(_domain).length > 0, "Empty domain not allowed");
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
    /**
     *  Check if a user can access a domain
     * @param _userDomain The domain of the user
     * @param _targetDomain The domain to check if the user can access 
     */
    function canAccessDomain(
        string memory _userDomain,
        string memory _targetDomain
    ) public view whenNotPaused returns (bool) {
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
