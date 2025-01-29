// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library VoterLib {
    struct Voter {
        uint256 votingPower;
        string emailDomain;
        bool canPropose;
    }
}