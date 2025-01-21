// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./platform_admin.sol";

contract VotingPlatform is PlatformAdmin {
    struct Proposal {
        string ipfsHash;
        string title;
        uint256 votedYes;
        uint256 votedNo;
        uint256 endTime;
        bool executed;
        string[] allowedDomains;
    }

    struct Voter {
        bool isRegistered;
        uint256 votingPower;
        string[] emailDomains;
    }

    mapping(address => Voter) public voters;
    mapping(string => Proposal) public proposals;
    mapping(string => mapping (address => bool)) hasVoted;
    string[] proposalHashes;

    uint256 public votingPeriod;

    constructor(uint256 _votingPeriod) {
        votingPeriod = _votingPeriod;
    }

    event VoterRegistered(address indexed voter);

    event ProposalCreated(
        string indexed ipfsHash,
        string title,
        address proposer
    );

    event VoteCast(
        string indexed ipfsHash,
        address indexed voter,
        bool support
    );
    event ProposalExecuted(string indexed ipfsHash);


    modifier onlyRegisteredVoter() {
        require(voters[msg.sender].isRegistered, "Not a registered voter");
        _;
    }

    function isVoterRegistered(string memory _domain) public view returns (bool) {
        string[] memory domains = voters[msg.sender].emailDomains;
        for (uint i = 0; i < domains.length; i++) {
            if (keccak256(bytes(domains[i])) == keccak256(bytes(_domain))) {
                return true;
            }
        }
        
        return false;
    }

    function registerWithDomain(string memory _domain) public {
        string memory domain = _domain;
        voters[msg.sender].isRegistered = true;
        voters[msg.sender].votingPower = 1;
        voters[msg.sender].emailDomains.push(domain);
        emit VoterRegistered(msg.sender);
    }

    function registerVoter(address _voter) public onlyAdmin {
        require(!voters[_voter].isRegistered, "Voter already registered");
        voters[_voter].isRegistered = true;
        voters[_voter].votingPower = 1;
        emit VoterRegistered(_voter);
    }

    function createProposal(
        string memory _ipfsHash,
        string memory _title,
        uint256 _startTime,
        string[] memory _allowedDomains
    ) public returns (string memory) {
        proposals[_ipfsHash] = Proposal(
            _ipfsHash,
            _title,
            0,
            0,
            _startTime + votingPeriod,
            false,
            _allowedDomains
        );
        proposalHashes.push(_ipfsHash);
        emit ProposalCreated(_ipfsHash, _title, msg.sender);
        return _ipfsHash;
    }

    function getAllProposals() public view returns (Proposal[] memory) {
    // Count matching proposals first
    uint256 matchingCount = 0;
    string[] memory voterDomains = voters[msg.sender].emailDomains;
    
    for (uint i = 0; i < proposalHashes.length; i++) {
        string memory hash = proposalHashes[i];
        Proposal memory proposal = proposals[hash];
        
        // Check if any voter domain matches proposal domains
        for (uint j = 0; j < voterDomains.length; j++) {
            for (uint k = 0; k < proposal.allowedDomains.length; k++) {
                if (keccak256(bytes(voterDomains[j])) == keccak256(bytes(proposal.allowedDomains[k]))) {
                    matchingCount++;
                    break;
                }
            }
        }
    }
    
    // Create array of correct size
    Proposal[] memory filteredProposals = new Proposal[](matchingCount);
    uint256 currentIndex = 0;
    
    // Fill array with matching proposals
    for (uint i = 0; i < proposalHashes.length; i++) {
        string memory hash = proposalHashes[i];
        Proposal memory proposal = proposals[hash];
        
        // Check if any voter domain matches proposal domains
        for (uint j = 0; j < voterDomains.length; j++) {
            for (uint k = 0; k < proposal.allowedDomains.length; k++) {
                if (keccak256(bytes(voterDomains[j])) == keccak256(bytes(proposal.allowedDomains[k]))) {
                    filteredProposals[currentIndex] = proposal;
                    currentIndex++;
                    break;
                }
            }
        }
    }
    return filteredProposals;
}

    function castVote(
        string memory __ipfsHash,
        bool _support
    ) public onlyRegisteredVoter {
        mapping(address => bool) storage votersList = hasVoted[__ipfsHash];
        Proposal storage proposal = proposals[__ipfsHash];
        require(block.timestamp >= proposal.endTime-votingPeriod, "Voting ended");
        require(block.timestamp < proposal.endTime, "Voting ended");
        require(!votersList[msg.sender], "Already voted");
        
        bool isDomainAllowed = false;
        for (uint j = 0; j < voters[msg.sender].emailDomains.length && !isDomainAllowed; j++) {
            string memory voterDomain = voters[msg.sender].emailDomains[j];
            for (uint i = 0; i < proposal.allowedDomains.length && !isDomainAllowed; i++) {
                if (keccak256(bytes(proposal.allowedDomains[i])) == keccak256(bytes(voterDomain))) {
                    isDomainAllowed = true;
                }
            }
        }
        require(isDomainAllowed, "Voter domain not allowed for this proposal");

        if (_support) {
            proposal.votedYes += voters[msg.sender].votingPower;
        } else {
            proposal.votedNo += voters[msg.sender].votingPower;
        }

        votersList[msg.sender] = true;

        emit VoteCast(__ipfsHash, msg.sender, _support);
    }
}
