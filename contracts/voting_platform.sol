// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./jwt_validator.sol";
import "./libraries/ProposalLib.sol";
import "./base/BaseVoting.sol";

contract VotingPlatform is JWTValidator, BaseVoting {
    using Base64 for string;
    using JsmnSolLib for string;
    using SolRsaVerify for *;
    using StringUtils for *;
    using ProposalLib for ProposalLib.Proposal;

    // removed "executed", we never use it and we can simply check endTime!

    // IPFS hash => Proposal
    mapping(string => ProposalLib.Proposal) public proposals;

    // Has voted ipfsHash => address[] of voters
    mapping(string => address[]) hasVoted;

    // List of all proposal hashes
    string[] proposalHashes;

    // Voting period in seconds
    uint256 public votingPeriod;

    /**
     *  Constructor for the VotingPlatform contract
     * @param _votingPeriod  The voting period in seconds
     * @param _admin  The address of the backend
     * @param _owner  The address of the owner
     */
    constructor(
        uint256 _votingPeriod,
        address _admin,
        address _owner
    ) JWTValidator(_admin, _owner) {
        votingPeriod = _votingPeriod;
    }

    /**
     *  Event emitted when a proposal is created
     * @param ipfsHash  The IPFS hash of the proposal
     * @param title  The title of the proposal
     * @param proposer  The address of the proposer
     */
    event ProposalCreated(
        string indexed ipfsHash,
        string title,
        address proposer
    );

    /**
     *  Event emitted when a vote is cast
     * @param ipfsHash  The IPFS hash of the proposal
     * @param voter  The address of the voter
     * @param support  Whether the voter supports the proposal
     */
    event VoteCast(
        string indexed ipfsHash,
        address indexed voter,
        bool support
    );

    /**
     * Modifier that allows the voter to cast a vote on a proposa
     */
    modifier onlyVoter() {
        require(voters[msg.sender].votingPower > 0, "Not a voter");
        _;
    }

    /**
     * Modifier that checks if the proposal is active
     */
    modifier isActive(string memory _ipfsHash) {
        require(
            proposals[_ipfsHash].endTime >= block.timestamp,
            "Proposal not active"
        );
        _;
    }

    /**
     * Check if the voter can vote on the proposal
     */
    modifier canVote(string memory _ipfsHash) {
        require(
            block.timestamp >= proposals[_ipfsHash].endTime - votingPeriod,
            "Voting not started yet"
        );
        require(block.timestamp < proposals[_ipfsHash].endTime, "Voting ended");
        require(
            canAccessDomain(
                voters[msg.sender].emailDomain,
                proposals[_ipfsHash].domain
            ),
            "Voter domain not allowed for this proposal"
        );

        address[] memory votersList = hasVoted[_ipfsHash];

        for (uint i = 0; i < votersList.length; i++) {
            require(votersList[i] != msg.sender, "Already voted");
        }
        _;
    }

    /**
     * Create a proposal
     * @param _ipfsHash The IPFS hash of the proposal
     * @param _voterAddress  The address of the voter that advanced the proposal
     * @param _restrictToDomain  Whether the proposal is restricted to the domain
     */
    function createProposal(
        string memory _ipfsHash,
        address _voterAddress,
        bool _restrictToDomain
    ) public onlyAdmin whenNotPaused returns (string memory) {
        // only domain representant

        // Check if domain is approved
        VoterLib.Voter storage voter = voters[_voterAddress];
        uint256 proposalExpiryDate = block.timestamp + votingPeriod;

        require(
            (domainConfigs[voter.emailDomain].expiryDate) >= proposalExpiryDate,
            "Domain expires before proposal ends"
        );

        proposals[_ipfsHash] = ProposalLib.Proposal(
            _ipfsHash,
            0,
            0,
            proposalExpiryDate,
            voter.emailDomain,
            _restrictToDomain
        );

        proposalHashes.push(_ipfsHash);
        return _ipfsHash;
    }

    /**
     * Get all proposals that the voter can access
     */
    function getAllProposals()
        public
        view
        whenNotPaused
        returns (ProposalLib.Proposal[] memory)
    {
        uint256 length = proposalHashes.length;
        ProposalLib.Proposal[] memory allProposals = new ProposalLib.Proposal[](
            length
        );
        uint256 validProposalCount = 0;

        for (uint256 i = 0; i < length; i++) {
            string memory ipfsHash = proposalHashes[i];
            ProposalLib.Proposal memory proposal = proposals[ipfsHash];
            // if proposal is restricted to domain, only voters from the same domain can access it
            if (
                proposal.restrictToDomain &&
                keccak256(abi.encodePacked(proposal.domain)) ==
                keccak256(abi.encodePacked(voters[msg.sender].emailDomain))
            ) {
                allProposals[validProposalCount] = proposals[ipfsHash];
                validProposalCount++;
            }
            // otherwise, check sub-parent domain relationship
            else if (
                canAccessDomain(
                    voters[msg.sender].emailDomain,
                    proposals[ipfsHash].domain
                )
            ) {
                allProposals[validProposalCount] = proposals[ipfsHash];
                validProposalCount++;
            }
        }
        // Create correctly sized array
        ProposalLib.Proposal[] memory result = new ProposalLib.Proposal[](
            validProposalCount
        );
        for (uint256 i = 0; i < validProposalCount; i++) {
            result[i] = allProposals[i];
        }
        return result;
    }

    /**
     *  Cast a vote on a proposal
     * @param _ipfsHash  The IPFS hash of the proposal
     * @param _support  Whether the voter supports the proposal
     */
    function castVote(
        string memory _ipfsHash,
        bool _support
    ) public nonReentrant whenNotPaused canVote(_ipfsHash) {
        require(
            voters[msg.sender].loginExpiry > block.timestamp,
            "Login expired"
        );
        ProposalLib.Proposal storage proposal = proposals[_ipfsHash];

        if (_support) {
            proposal.votedYes += voters[msg.sender].votingPower;
        } else {
            proposal.votedNo += voters[msg.sender].votingPower;
        }

        address[] storage votersList = hasVoted[_ipfsHash];

        votersList.push(msg.sender);
    }

    /**
     * Register a voter with a domain
     * @param _headerJson  The header of the JWT
     * @param _payload  The payload of the JWT
     * @param _signature  The signature used on the JWT
     */
    function registerWithDomain(
        string memory _headerJson,
        string memory _payload,
        bytes memory _signature
    ) public whenNotPaused returns (string memory) {
        // If the voter has not been registered yet, add them to the list addressToEmail
        (string memory domain, string memory parsedEmail) = parseJWT(
            _headerJson,
            _payload,
            _signature
        );
        bytes32 encodedMail = keccak256(abi.encodePacked(parsedEmail));
        // Check if email is already registered to another address
        require(
            emailToAddress[encodedMail] == address(0) ||
                emailToAddress[encodedMail] == msg.sender,
            "Email already registered to different address"
        );

        // Check if address is already registered with different email
        require(
            addressToEmail[msg.sender] == bytes32(0) ||
                addressToEmail[msg.sender] == encodedMail,
            "Address already registered with different email"
        );
        //bytes32 encodedMail = keccak256(abi.encodePacked(parsedEmail));
        if (isDomainRegistered(domain)) {
            addressToEmail[msg.sender] = encodedMail;
            emailToAddress[encodedMail] = msg.sender;
            _registerVoter(
                msg.sender,
                domain,
                domainConfigs[domain].powerLevel
            );
        } else {
            revert("User already registered or domain issues");
        }
        return domain;
    }

    /**
     * Login a voter
     * @param _headerJson The header of the JWT
     * @param _payloadJson  The payload of the JWT
     * @param _signature  The signature used on the JWT
     */
    function login(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature
    ) public whenNotPaused returns (bool) {
        (string memory domain, string memory parsedEmail) = parseJWT(
            _headerJson,
            _payloadJson,
            _signature
        );
        bytes32 senderEmail = addressToEmail[msg.sender];

        // added domain check upon login attempt as domains can now EXPIRE!!!
        require(isDomainRegistered(domain), "domain expired! must renew!");
        require(
            senderEmail == keccak256(abi.encodePacked(parsedEmail)),
            "Registered email does not match login one"
        );
        voters[msg.sender].loginExpiry = block.timestamp + 20 minutes;
        return true;
    }
}
