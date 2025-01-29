// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;


import "../libraries/VoterLib.sol";

abstract contract BaseVoting {
    using VoterLib for VoterLib.Voter;
    
    mapping(address => VoterLib.Voter) public voters;
    mapping(address => bytes32) public addressToEmail;
    
    event VoterRegistered(address indexed voter);
    
    function _registerVoter(address _voter, string memory _domain, uint256 _power) internal {
        voters[_voter] = VoterLib.Voter({
            votingPower: _power,
            emailDomain: _domain,
            canPropose: false
        });
        emit VoterRegistered(_voter);
    }
}