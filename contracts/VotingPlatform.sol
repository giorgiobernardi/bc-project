// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

contract VotingPlatform {
    struct Proposal {
        string title;
        string description;
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

    mapping(address => bool) public admins;
    mapping(address => mapping(address => bool)) public adminApprovals;
    mapping(address => uint256) public pendingAdminApprovalCount;
    mapping(address => uint256) public adminProposalTime;

    uint256 public proposalCount;
    address public admin;
    uint256 public minVotingDelay;
    uint256 public votingPeriod;
    uint256 public adminCount;
    uint256 public constant MIN_ADMINS = 1;
    uint256 public constant ADMIN_PROPOSAL_COOLDOWN = 1 days;

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
    event AdminProposed(address indexed proposer, address indexed newAdmin);
    event AdminApproved(address indexed approver, address indexed newAdmin);
    event AdminRemoved(address indexed admin);

    constructor(uint256 _minVotingDelay, uint256 _votingPeriod) {
        admins[msg.sender] = true;
        adminCount = 1;
        minVotingDelay = _minVotingDelay;
        votingPeriod = _votingPeriod;
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

    function isAdmin(address _account) external view returns (bool) {
        return admins[_account];
    }

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
        string memory _description,
        uint256 _startTime
    ) public onlyRegisteredVoter returns (uint256) {
        require(
            _startTime >= block.timestamp + minVotingDelay,
            "Start time too soon"
        );

        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.title = _title;
        proposal.description = _description;
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

    // Add more functions as needed:
    // - Get proposal details
    // - Execute proposal
    // - Change voting parameters
    // - Delegate votes
    // - etc.
}
