// SPDX-License-Identifier: MIT
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

    error InvalidSignature(
        string message,
        bytes signature,
        bytes exponent,
        bytes modulus
    );
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

    constructor(address _admin, address _owner) PlatformAdmin(_admin, _owner) {}

    // kid => modulus
    mapping(string kid => bytes) private _modulo;

    // Track all key IDs
    string[] private _keyIds; // Track all key IDs

    struct GoogleModule {
        string kid;
        bytes modulus;
    }

    /**
     * Modulus is the n value of the public key of the JWT issuer
     * kid is the key ID of the public key used to sign the JWT
     * @param googleModule Array of GoogleModule
     */
    function addModulus(
        GoogleModule[] memory googleModule
    ) external whenNotPaused onlyOwner {
        for (uint i = 0; i < googleModule.length; i++) {
            _modulo[googleModule[i].kid] = googleModule[i].modulus;
            _keyIds.push(googleModule[i].kid);
        }
    }

    /**
     * Retrieve all moduli used by Google to sign JWTs
     */
    function getAllModuli() public view whenNotPaused returns (bytes[] memory) {
        bytes[] memory moduli = new bytes[](_keyIds.length);
        for (uint i = 0; i < _keyIds.length; i++) {
            moduli[i] = _modulo[_keyIds[i]];
        }
        return moduli;
    }

    /**
     * Retrieve the particular modulus used by Google to sign JWTs fetching it from the kid
     * @param kid  The key ID of the public key used to sign the JWT
     */
    function getModulus(
        string memory kid
    ) public view whenNotPaused returns (bytes memory) {
        return _modulo[kid];
    }

    /**
     * Parses the JWT and validates the signature
     * @param _headerJson  The header of the JWT, contains the key ID.
     * @param _payloadJson The payload of the JWT, contains the email and nonce.
     * @param _signature The signer of the JWT
     * @return domain The domain of the email
     * @return parsedEmail The email of the user
     */
    function parseJWT(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature
    ) internal view returns (string memory domain, string memory parsedEmail) {
        string memory email = validateJwt(
            _headerJson,
            _payloadJson,
            _signature,
            msg.sender
        );

        // Create a slice from email
        StringUtils.slice memory emailSlice = email.toSlice();
        StringUtils.slice memory atSign = "@".toSlice();

        // Split and keep only the domain part
        emailSlice.split(atSign); // This discards everything before @
        domain = emailSlice.toString(); // Get the domain as string

        if (!isDomainRegistered(domain)) {
            revert("Domain not registered by the admin OR domain expired");
        }
        return (domain, email);
    }

    /**
     * Validate the JWT by verifying the signature and checking the nonce
     * @param _headerJson The header of the JWT
     * @param _payloadJson The payload of the JWT
     * @param _signature The signer of the JWT
     * @param _receiver The address of the receiver
     */
    function validateJwt(
        string memory _headerJson,
        string memory _payloadJson,
        bytes memory _signature,
        address _receiver
    ) internal view returns (string memory) {
        string memory headerBase64 = _headerJson.encode();
        string memory payloadBase64 = _payloadJson.encode();

        StringUtils.slice[] memory slices = new StringUtils.slice[](2);
        slices[0] = headerBase64.toSlice();
        slices[1] = payloadBase64.toSlice();
        string memory message = ".".toSlice().join(slices);

        string memory kid = parseHeader(_headerJson);

        bytes memory exponent = getRsaExponent(kid);
        bytes memory modulus = getRsaModulus(kid);

        if (message.pkcs1Sha256VerifyStr(_signature, exponent, modulus) != 0) {
            revert InvalidSignature(message, _signature, exponent, modulus);
        }

        (string memory nonce, string memory email) = parseToken(_payloadJson);

        // JWT nonce should be receiver to prevent frontrunning
        string memory senderBase64 = string(abi.encodePacked(_receiver))
            .encode();

        if (senderBase64.strCompare(nonce) != 0) {
            revert InvalidNonce(nonce, _receiver);
        }
        return email;
    }

    /**
     * Compare the kid in the header of the JWT to the kid in the Google public key
     * @param json The header of the JWT
     */
    function parseHeader(
        string memory json
    ) internal pure returns (string memory kid) {
        (
            uint256 exitCode,
            JsmnSolLib.Token[] memory tokens,
            uint256 ntokens
        ) = json.parse(20);
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

    /**
     *  Parse the payload of the JWT
     * @param json  The payload of the JWT
     * @return nonce  The nonce of the JWT
     * @return email  The email of the user
     */
    function parseToken(
        string memory json
    ) internal pure returns (string memory nonce, string memory email) {
        (
            uint256 exitCode,
            JsmnSolLib.Token[] memory tokens,
            uint256 ntokens
        ) = json.parse(40);
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

    /**
     * Retrieve the modulus used by Google to sign JWTs
     * @param kid The key ID of the public key used to sign the JWT
     */
    function getRsaModulus(
        string memory kid
    ) internal view returns (bytes memory modulus) {
        modulus = getModulus(kid);
        if (modulus.length == 0) {
            revert UnknownKid(kid);
        }
    }

    /**
     *  Retrieve the exponent used by Google to sign JWTs
     */
    function getRsaExponent(
        string memory
    ) internal pure returns (bytes memory) {
        return
            hex"00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010001";
    }
}
