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
    }

    struct Voter {
        bool isRegistered;
        uint256 votingPower;
    }

    mapping(address => Voter) public voters;
    mapping(string => Proposal) public proposals;
    mapping(string => mapping (address => bool)) hasVoted;
    // TODO refactor hasVoted, we don't need to store all this data! a simple mapping(string => address[]) should be enough
    // this way we can store the proposal hash and the addresses of the voters that have voted
    // I don't want to break everything so I'll leave that for later
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

    function registerVoter(address _voter) public onlyAdmin {
        require(!voters[_voter].isRegistered, "Voter already registered");
        voters[_voter].isRegistered = true;
        voters[_voter].votingPower = 1;
        emit VoterRegistered(_voter);
    }

    function createProposal(
        string memory _ipfsHash,
        string memory _title,
        uint256 _startTime

    ) public returns (string memory) {
        proposals[_ipfsHash] = Proposal(
            _ipfsHash,
            _title,
            0,
            0,
            _startTime + votingPeriod,
            false
        );
        proposalHashes.push(_ipfsHash);
        emit ProposalCreated(_ipfsHash, _title, msg.sender);
        return _ipfsHash;
    }

 function getAllProposals() public view returns (Proposal[] memory) {
    Proposal[] memory allProposals = new Proposal[](proposalHashes.length);
    
    for (uint i = 0; i < proposalHashes.length; i++) {
        string memory hash = proposalHashes[i];
        Proposal memory proposal = proposals[hash];
        allProposals[i] = proposal;
    }

    return allProposals;
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

        if (_support) {
            proposal.votedYes += voters[msg.sender].votingPower;
        } else {
            proposal.votedNo += voters[msg.sender].votingPower;
        }

        votersList[msg.sender] = true;

        emit VoteCast(__ipfsHash, msg.sender, _support);
    }
}
