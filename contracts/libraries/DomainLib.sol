// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

library DomainLib {
    struct DomainConfig {
        string domain;
        uint128 powerLevel;
        uint256 expiryDate;
    }
}