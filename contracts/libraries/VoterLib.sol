// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library VoterLib {
    struct Voter {
        uint128 votingPower;
        string emailDomain;
        bool canPropose;
    }
}