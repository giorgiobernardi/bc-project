// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ProposalLib {
    struct Proposal {
        string ipfsHash;
        uint128 votedYes; 
        uint128 votedNo; 
        uint256 endTime;
        string domain;
        bool restrictToDomain;
    }
}
