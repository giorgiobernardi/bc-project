// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./jwt_validator.sol";
import "hardhat/console.sol";


contract VotingPlatform is JWTValidator {
    
    using Base64 for string;
    using JsmnSolLib for string;
    using SolRsaVerify for *;
    using StringUtils for *;

    // removed "executed", we never use it and we can simply check endTime!
    struct Proposal {
        string ipfsHash;
        string title;
        uint256 votedYes;
        uint256 votedNo;
        uint256 endTime;
        string domain;
        bool restrictToDomain; // if true, only voters from the same domain can access it
    }

    struct Voter {
        uint256 votingPower;
        string emailDomain;
        bool canPropose;
    }

    mapping(address => Voter) public voters;

    // Voter has a unique email associated through which they can interact with the platform
    mapping(address => bytes32) private addressToEmail;

    // IPFS hash => Proposal
    mapping(string => Proposal) public proposals;

    // Has voted ipfsHash => address[] of voters
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
            block.timestamp < proposals[_ipfsHash].endTime,
            "Voting ended"
        );

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

    function registerWithDomain(
        string memory _headerJson,
        string memory _payload,
        bytes memory _signature
    ) public {
        // Parse JWT and get email
        string memory parsedEmail = parseJWT(
            _headerJson,
            _payload,
            _signature
        );
        
        bytes32 encodedMail = keccak256(abi.encodePacked(parsedEmail));

        if (addressToEmail[msg.sender] != encodedMail) {
            // Extract domain using StringUtils
            StringUtils.slice memory emailSlice = parsedEmail.toSlice();
            StringUtils.slice memory atSign = "@".toSlice();
            StringUtils.slice memory username;
            StringUtils.slice memory domain;
            emailSlice.split(atSign, username);

            domain = emailSlice; // After split, emailSlice contains everything after @
            

            // Get domain as string
            string memory domainStr = domain.toString();
            
            // Verify domain is registered
            require(isDomainRegistered(domainStr), "Domain not registered");
            
            // Store voter info
            addressToEmail[msg.sender] = encodedMail;
            voters[msg.sender].emailDomain = domainStr;
            voters[msg.sender].votingPower = domainConfigs[domainStr].powerLevel;
            
            
            emit VoterRegistered(msg.sender);
        } else {
            revert("User already registered");
        }
    }

    function addProposer(address _voterAddr) public onlyAdmin {
        voters[_voterAddr].canPropose = true;
    }
    function removeProposer(address _voterAddr) public onlyAdmin {
        voters[_voterAddr].canPropose = false;
    }


    function createProposal(
        string memory _ipfsHash,
        string memory _title,
        bool _restrictToDomain
    ) public returns (string memory) { // only domain representant

        // Check if domain is approved
        
        require(voters[msg.sender].canPropose || isAdmin(msg.sender), "Not allowed to propose");
        Voter storage voter = voters[msg.sender];

        proposals[_ipfsHash] = Proposal(
            _ipfsHash,
            _title,
            0,
            0,
            block.timestamp + votingPeriod,
            voter.emailDomain,
            _restrictToDomain
        );
        proposalHashes.push(_ipfsHash);

        emit ProposalCreated(_ipfsHash, _title, msg.sender);

        return _ipfsHash;
    }

    function getAllProposals() public view returns (Proposal[] memory) {
        Proposal[] memory allProposals = new Proposal[](proposalHashes.length);
        uint256 validProposalCount = 0;

        for (uint256 i = 0; i < proposalHashes.length; i++) {
            string memory ipfsHash = proposalHashes[i];
            Proposal memory proposal = proposals[ipfsHash];
            // if proposal is restricted to domain, only voters from the same domain can access it
            if (proposal.restrictToDomain && keccak256(abi.encodePacked(proposal.domain)) == keccak256(abi.encodePacked(voters[msg.sender].emailDomain))) {
                allProposals[validProposalCount] = proposals[ipfsHash];
                validProposalCount++;
            }
            // otherwise, check sub-parent domain relationship
            else if (canAccessDomain(
                voters[msg.sender].emailDomain,
                proposals[ipfsHash].domain
            )) {
                allProposals[validProposalCount] = proposals[ipfsHash];
                validProposalCount++;
            }
        }
        // Create correctly sized array
        Proposal[] memory result = new Proposal[](validProposalCount);
        for (uint256 i = 0; i < validProposalCount; i++) {
            result[i] = allProposals[i];
        }
        return result;
    }

    function castVote(
        string memory _ipfsHash,
        bool _support
    ) public canVote(_ipfsHash) {
        Proposal storage proposal = proposals[_ipfsHash];
        
        if (_support) {
            proposal.votedYes += voters[msg.sender].votingPower;
        } else {
            proposal.votedNo += voters[msg.sender].votingPower;
        }

        address[] storage votersList = hasVoted[_ipfsHash];

        votersList.push(msg.sender);

        emit VoteCast(_ipfsHash, msg.sender, _support);
    }



    function login(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature
    ) public view returns (bool) {
        string memory parsedEmail = validateJwt(
            _headerJson,
            _payloadJson,
            _signature,
            msg.sender
        );
        bytes32 senderEmail = addressToEmail[msg.sender];

        require(
            senderEmail == keccak256(abi.encodePacked(parsedEmail)),
            "Registered email does not match login one"
        );
        return true;
    }
}
