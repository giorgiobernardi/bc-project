pragma solidity ^0.8.28;

import {Base64} from "../libs/Base64.sol";
import {JsmnSolLib} from "../libs/JsmnSolLib.sol";
import {SolRsaVerify} from "../libs/SolRsaVerify.sol";
import {StringUtils} from "../libs/Strings.sol";

import "./platform_admin.sol";

contract JWTValidator is PlatformAdmin {
 
    uint256 internal _tokenIdCounter;
    
    using Base64 for string;
    using JsmnSolLib for string;
    using StringUtils for *;
    using SolRsaVerify for *;

   error InvalidSignature(string message, bytes signature, bytes exponent, bytes modulus);
    error InvalidAudience(string aud, string expectedAudience);
    error InvalidNonce(string nonce, address receiver);
    error InvalidDomain(string email, string domain);
    error AlreadyClaimed(string email);

    error JSONParseFailed();
    error ExpectedJWTToBeAnObject();
    error ExpectedJWTToContainOnlyStringKeys();
    error ExpectedKidToBeAString();
    error ExpectedAudToBeAString();
    error ExpectedNonceToBeAString();
    error ExpectedEmailToBeAString();
    error UnknownKid(string kid);

    constructor(address _admin) PlatformAdmin(_admin){}

    // TODO: refactor addModulus so that onlyAdmin can call them, to do so,
    // make them internal and call them from the VotingPlatform contract! NOT SURE IF THAT'S HOW IT WORKS :))
    // @Ulises to @Giorgio: It should suffice to use the onlyAdmin modifier in the method signature
    mapping(string kid => bytes) private modulo;
    string[] private keyIds;  // Track all key IDs
    
    

    function addModulus(string memory kid, bytes memory modulus) external onlyAdmin{
        
        modulo[kid] = modulus;
        
        keyIds.push(kid);
    }

    function getAllModuli() public view returns (bytes[] memory) {
        bytes[] memory moduli = new bytes[](keyIds.length);
        for (uint i = 0; i < keyIds.length; i++) {
            moduli[i] = modulo[keyIds[i]];
        }
        return moduli;
    }
    
    function getModulus(string memory kid) public view returns (bytes memory) {
        return modulo[kid];
    }

   function parseJWT(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature
    ) internal view returns (string memory) {
        string memory email = validateJwt(
            _headerJson,
            _payloadJson,
            _signature,
            msg.sender
        );
        console.log("Email: %s", email);
        string memory emailDomain = email
            .toSlice()
            .split("@".toSlice())
            .toString();

        console.log("Email domain: %s", emailDomain);
        if (!isDomainRegistered(emailDomain)) {
            revert("Domain not registered by the admin");
        }
        return email;
    }


    function validateJwt(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature,
        address _receiver
    ) internal view returns (string memory) {

        string memory headerBase64 = _headerJson.encode();
        string memory payloadBase64 = _payloadJson.encode();
        //console.log("HeaderJson: %s", _headerJson);
        //console.log("PayloadJson: %s", _payloadJson);
        StringUtils.slice[] memory slices = new StringUtils.slice[](2);
        slices[0] = headerBase64.toSlice();
        slices[1] = payloadBase64.toSlice();
        string memory message = ".".toSlice().join(slices);
        //console.log("Message: %s", message);
        string memory kid = parseHeader(_headerJson);
        //console.log("Kid: %s", kid);
        bytes memory exponent = getRsaExponent(kid);
        bytes memory modulus = getRsaModulus(kid);

        if (message.pkcs1Sha256VerifyStr(_signature, exponent, modulus) != 0) {
            revert InvalidSignature(message, _signature, exponent, modulus);
        }

        (string memory aud, string memory nonce, string memory email) = parseToken(_payloadJson);
        
        // if (aud.strCompare(audience) != 0) {
        //     revert;
        // }

        // JWT nonce should be receiver to prevent frontrunning
        string memory senderBase64 = string(abi.encodePacked(_receiver)).encode();

        if (senderBase64.strCompare(nonce) != 0) {
            revert InvalidNonce(nonce, _receiver);
        }
        return email;
    }

    function parseHeader(string memory json) internal pure returns (string memory kid) {
        (uint256 exitCode, JsmnSolLib.Token[] memory tokens, uint256 ntokens) = json.parse(20);
        if (exitCode != 0) {
   
            revert JSONParseFailed();
        }

        if (tokens[0].jsmnType != JsmnSolLib.JsmnType.OBJECT) {
         
            revert ExpectedJWTToBeAnObject();
        }
        uint256 i = 1;
        while (i < ntokens) {
            if (tokens[i].jsmnType != JsmnSolLib.JsmnType.STRING) {
         
                revert ExpectedJWTToContainOnlyStringKeys();
            }
            string memory key = json.getBytes(tokens[i].start, tokens[i].end);
            if (key.strCompare("kid") == 0) {
                if (tokens[i + 1].jsmnType != JsmnSolLib.JsmnType.STRING) {
            
                    revert ExpectedKidToBeAString();
                }
                return json.getBytes(tokens[i + 1].start, tokens[i + 1].end);
            }
            i += 2;
        }
    }

    function parseToken(string memory json)
        internal
        pure
        returns (string memory aud, string memory nonce, string memory email)
    {
        (uint256 exitCode, JsmnSolLib.Token[] memory tokens, uint256 ntokens) = json.parse(40);
        if (exitCode != 0) {
      
            revert JSONParseFailed();
        }

        if (tokens[0].jsmnType != JsmnSolLib.JsmnType.OBJECT) {
    
            revert ExpectedJWTToBeAnObject();
        }
        uint256 i = 1;
        while (i < ntokens) {
            if (tokens[i].jsmnType != JsmnSolLib.JsmnType.STRING) {
   
                revert ExpectedJWTToContainOnlyStringKeys();
            }
            string memory key = json.getBytes(tokens[i].start, tokens[i].end);
            if (key.strCompare("aud") == 0) {
                if (tokens[i + 1].jsmnType != JsmnSolLib.JsmnType.STRING) {
 
                    revert ExpectedAudToBeAString();
                }
                aud = json.getBytes(tokens[i + 1].start, tokens[i + 1].end);
            } else if (key.strCompare("nonce") == 0) {
                if (tokens[i + 1].jsmnType != JsmnSolLib.JsmnType.STRING) {
      
                    revert ExpectedNonceToBeAString();
                }
                nonce = json.getBytes(tokens[i + 1].start, tokens[i + 1].end);
            } else if (key.strCompare("email") == 0) {
                if (tokens[i + 1].jsmnType != JsmnSolLib.JsmnType.STRING) {
               
                    revert ExpectedEmailToBeAString();
                }
                email = json.getBytes(tokens[i + 1].start, tokens[i + 1].end);
            }
            i += 2;
        }
    }

    

    function getRsaModulus(string memory kid) internal view returns (bytes memory modulus) {
        modulus = getModulus(kid);
        if (modulus.length == 0) {
            revert UnknownKid(kid);
        }
    }

    function getRsaExponent(string memory) internal pure returns (bytes memory) {
        return
        hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010001";
    }

}