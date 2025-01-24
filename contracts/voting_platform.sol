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
        string domain;
    }

    struct Voter {
        uint256 votingPower;
        string emailDomain;
    }

    mapping(address => Voter) public voters;
    mapping(string => Proposal) public proposals;
    mapping(string => mapping(address => bool)) hasVoted;
    string[] proposalHashes;

    uint256 public votingPeriod;

    constructor(uint256 _votingPeriod, address _admin) PlatformAdmin(_admin) {
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

    // function isVoterRegistered(string memory _domain) public view returns (bool) {
    //     string[] memory domains = voters[msg.sender].domain;
    //     for (uint i = 0; i < domains.length; i++) {
    //         if (keccak256(bytes(domains[i])) == keccak256(bytes(_domain))) {
    //             return true;
    //         }
    //     }
    //     return false;
    // }

    function registerWithDomain(string memory _domain) public {
        require(approvedDomains[_domain], "Domain not approved");
        voters[msg.sender].votingPower = 1;
        // voters[msg.sender].emailDomains.push(_domain);
        emit VoterRegistered(msg.sender);
    }

    function createProposal(
        string memory _ipfsHash,
        string memory _title,
        uint256 _startTime // TODO: get it from an Oracle
    ) public returns (string memory) {
        Voter storage voter = voters[msg.sender];

        proposals[_ipfsHash] = Proposal(
            _ipfsHash,
            _title,
            0,
            0,
            _startTime + votingPeriod,
            false,
            voter.emailDomain
        );
        proposalHashes.push(_ipfsHash);
        emit ProposalCreated(_ipfsHash, _title, msg.sender);
        return _ipfsHash;
    }

    function getAllProposals() public view returns (Proposal[] memory) {
        // Count matching proposals first
        uint256 matchingCount = 0;
        string memory voterDomain = voters[msg.sender].emailDomain;
        Proposal[] memory filteredProposals = new Proposal[](
            proposalHashes.length
        );
        uint currentIndex = 0;
        // Fill array with matching proposals
        for (uint i = 0; i < proposalHashes.length; i++) {
            string memory hash = proposalHashes[i];
            Proposal memory proposal = proposals[hash];

            // Check if any voter domain matches proposal domains
            if (
                keccak256(bytes(voterDomain)) ==
                keccak256(bytes(proposal.domain))
            ) {
                filteredProposals[currentIndex] = proposal;
                currentIndex++;
            }
        }
        return filteredProposals;
    }

    function castVote(string memory __ipfsHash, bool _support) public {
        mapping(address => bool) storage votersList = hasVoted[__ipfsHash];
        Proposal storage proposal = proposals[__ipfsHash];
        require(
            block.timestamp >= proposal.endTime - votingPeriod,
            "Voting ended"
        ); // TODO: review with Oracle in mind
        require(block.timestamp < proposal.endTime, "Voting ended");
        require(!votersList[msg.sender], "Already voted");

        require(
            keccak256(bytes(proposal.domain)) ==
                keccak256(bytes(voters[msg.sender].emailDomain)),
            "Voter domain not allowed for this proposal"
        );

        if (_support) {
            proposal.votedYes += voters[msg.sender].votingPower;
        } else {
            proposal.votedNo += voters[msg.sender].votingPower;
        }

        votersList[msg.sender] = true;

        emit VoteCast(__ipfsHash, msg.sender, _support);
    }
}
