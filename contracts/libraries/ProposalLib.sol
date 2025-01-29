// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library ProposalLib {
    struct Proposal {
        string ipfsHash;
        string title;
        uint256 votedYes;
        uint256 votedNo;
        uint256 endTime;
        string domain;
        bool restrictToDomain;
    }
}