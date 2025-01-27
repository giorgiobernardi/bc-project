// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./jwt_validator.sol";

contract VotingPlatform is JWTValidator {
    using Base64 for string;
    using JsmnSolLib for string;
    using SolRsaVerify for *;
    using StringUtils for *;

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
        bool canPropose;
    }

    mapping(address => Voter) public voters;

    // Voter has a unique email associated throught which they can interact with the platform
    mapping(address => bytes32) private addressToEmail;

    // IPFS hash => Proposal
    mapping(string => Proposal) public proposals;

    // Proposal ID => Email hash => Has voted ipfsHash => address[]
    mapping(string => address[]) hasVoted;

    string[] proposalHashes;

    uint256 public votingPeriod;

    constructor(uint256 _votingPeriod, address _admin) JWTValidator(_admin) {
        votingPeriod = _votingPeriod;
    }

    function setVotingPeriod(uint256 _votingPeriod) public onlyAdmin {
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

    modifier onlyVoter() {
        require(voters[msg.sender].votingPower > 0, "Not a voter");
        _;
    }

    modifier isActive(string memory _ipfsHash) {
        require(
            proposals[_ipfsHash].endTime >= block.timestamp,
            "Proposal not active"
        );
        _;
    }

    modifier canVote(string memory _ipfsHash) {
        require(
            block.timestamp >= proposals[_ipfsHash].endTime - votingPeriod,
            "Voting not started yet"
        );

        require(
            block.timestamp >= proposals[_ipfsHash].endTime - votingPeriod,
            "Voting ended"
        );

        require(
            keccak256(bytes(proposals[_ipfsHash].domain)) ==
                keccak256(bytes(voters[msg.sender].emailDomain)),
            "Voter domain not allowed for this proposal"
        );

        address[] memory votersList = hasVoted[_ipfsHash];

        for (uint i = 0; i < votersList.length; i++) {
            require(votersList[i] != msg.sender, "Already voted");
        }

        _;
    }

    function registerWithDomain(
        string memory _headerJson,
        string memory _payload,
        bytes memory _signature
    ) public {
        // If the voter has not been registered yet, add them to the list addressToEmail
        string memory parsedEmail = parseJWT(
            _headerJson,
            _payload,
            _signature
        );
        bytes32 encodedMail = keccak256(abi.encodePacked(parsedEmail));
        
        if (addressToEmail[msg.sender] != encodedMail) {
            addressToEmail[msg.sender] = encodedMail;
            voters[msg.sender].votingPower = 1;

            emit VoterRegistered(msg.sender);
        } else {
            revert("User already registered");
        }
    }

    function addProposer(address _voterAddr) public onlyAdmin {
        voters[_voterAddr].canPropose = true;
    }
    function removePropose(address _voterAddr) public onlyAdmin {
        voters[_voterAddr].canPropose = false;
    }



    function createProposal(
        string memory _ipfsHash,
        string memory _title,
        uint256 _startTime
    ) public returns (string memory) { // only domain representant

        // Check domain is approved
        
        require(voters[msg.sender].canPropose || isAdmin(msg.sender), "Not allowed to propose");
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

    function castVote(
        string memory __ipfsHash,
        bool _support
    ) public canVote(__ipfsHash) {
        
        Proposal storage proposal = proposals[__ipfsHash];

        if (_support) {
            proposal.votedYes += voters[msg.sender].votingPower;
        } else {
            proposal.votedNo += voters[msg.sender].votingPower;
        }

        address[] storage votersList = hasVoted[__ipfsHash];

        votersList.push(msg.sender);

        emit VoteCast(__ipfsHash, msg.sender, _support);
    }

    function parseJWT(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature
    ) private view returns (string memory) {
        string memory email = validateJwt(
            _headerJson,
            _payloadJson,
            _signature,
            msg.sender
        );

        string memory emailDomain = email
            .toSlice()
            .split("@".toSlice())
            .toString();

        if (!isDomainRegistered(emailDomain)) {
            revert("Domain not registered by the admin");
        }
        return email;
    }

    function login(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature,
        address _sender
    ) public view returns (bool) {
        string memory parsedEmail = validateJwt(
            _headerJson,
            _payloadJson,
            _signature,
            _sender
        );
        bytes32 senderEmail = addressToEmail[msg.sender];

        require(
            senderEmail == keccak256(abi.encodePacked(parsedEmail)),
            "Registered email does not match login one"
        );

        return true;
    }
}
