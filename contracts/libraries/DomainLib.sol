// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library DomainLib {
    struct DomainConfig {
        string domain;
        uint256 powerLevel;
        uint256 expiryDate;
    }
}