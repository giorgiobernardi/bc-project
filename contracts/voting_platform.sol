// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./platform_admin.sol";

contract VotingPlatform is PlatformAdmin {
    struct Proposal {
        string proposalHash;
        string ipfsHash;
        string title;
        uint256 voteCount;
        uint256 startTime;
        uint256 endTime;
        bool executed;
        mapping(address => bool) hasVoted;
    }

    struct Voter {
        bool isRegistered;
        uint256 votingPower;
        uint256 lastVoteTime;
    }

    mapping(address => Voter) public voters;
    mapping(uint256 => Proposal) public proposals;

    uint256 public proposalCount;
    uint256 public minVotingDelay;
    uint256 public votingPeriod;

    constructor(uint256 _minVotingDelay, uint256 _votingPeriod) {
        minVotingDelay = _minVotingDelay;
        votingPeriod = _votingPeriod;
    }

    event VoterRegistered(address indexed voter);

    event ProposalCreated(
        uint256 indexed proposalId,
        string title,
        address proposer
    );

    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        bool support
    );
    event ProposalExecuted(uint256 indexed proposalId);


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
        string memory _title,
        uint256 _startTime
    ) public onlyRegisteredVoter returns (uint256) {
        require(
            _startTime >= block.timestamp + minVotingDelay,
            "Start time too soon"
        );

        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.title = _title;
        proposal.startTime = _startTime;
        proposal.endTime = _startTime + votingPeriod;

        emit ProposalCreated(proposalId, _title, msg.sender);
        return proposalId;
    }

    function castVote(
        uint256 _proposalId,
        bool _support
    ) public onlyRegisteredVoter {
        Proposal storage proposal = proposals[_proposalId];
        require(block.timestamp >= proposal.startTime, "Voting not started");
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!proposal.hasVoted[msg.sender], "Already voted");

        if (_support) {
            proposal.voteCount += voters[msg.sender].votingPower;
        }

        proposal.hasVoted[msg.sender] = true;
        voters[msg.sender].lastVoteTime = block.timestamp;

        emit VoteCast(_proposalId, msg.sender, _support);
    }
}
