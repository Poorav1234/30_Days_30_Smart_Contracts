// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract ProductionDID is AccessControl, EIP712, ReentrancyGuard {

    using ECDSA for bytes32;

    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    struct DID {
        address controller;
        bool active;
        uint256 createdAt;
        uint256 updatedAt;
    }

    mapping(bytes32 => DID) private dids;

    mapping(bytes32 => mapping(address => bool)) private didKeys;

    struct Credential {
        bytes32 did;
        address issuer;
        bytes32 dataHash;
        uint256 issuedAt;
        bool revoked;
    }

    mapping(bytes32 => Credential) private credentials;

    bytes32 private constant DID_TYPEHASH =
        keccak256("RegisterDID(bytes32 did,address controller)");

    bytes32 private constant CREDENTIAL_TYPEHASH =
        keccak256("IssueCredential(bytes32 credentialId,bytes32 did,bytes32 dataHash)");

    event DIDRegistered(bytes32 indexed did, address controller);
    event KeyRotated(bytes32 indexed did, address newKey);
    event DIDRevoked(bytes32 indexed did);
    event CredentialIssued(bytes32 indexed credentialId, bytes32 did);
    event CredentialRevoked(bytes32 indexed credentialId);

    constructor()
        EIP712("ProductionDID", "1")
    {
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function registerDID(
        bytes32 _did,
        address _controller,
        bytes calldata signature
    ) external nonReentrant {

        require(dids[_did].controller == address(0), "DID exists");

        bytes32 structHash = keccak256(
            abi.encode(DID_TYPEHASH, _did, _controller)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        require(signer == _controller, "Invalid signature");

        dids[_did] = DID({
            controller: _controller,
            active: true,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        didKeys[_did][_controller] = true;

        emit DIDRegistered(_did, _controller);
    }

    function rotateKey(bytes32 _did, address _newKey)
        external
    {
        require(dids[_did].controller == msg.sender, "Not controller");
        require(dids[_did].active, "DID inactive");
        require(_newKey != address(0), "Invalid key");

        didKeys[_did][_newKey] = true;
        dids[_did].updatedAt = block.timestamp;

        emit KeyRotated(_did, _newKey);
    }

    function revokeDID(bytes32 _did) external {
        require(dids[_did].controller == msg.sender, "Not controller");
        require(dids[_did].active, "Already revoked");

        dids[_did].active = false;
        dids[_did].updatedAt = block.timestamp;

        emit DIDRevoked(_did);
    }

    function issueCredential(
        bytes32 _credentialId,
        bytes32 _did,
        bytes32 _dataHash,
        bytes calldata signature
    ) external onlyRole(ISSUER_ROLE) nonReentrant {

        require(dids[_did].active, "DID inactive");
        require(credentials[_credentialId].issuer == address(0), "Exists");

        bytes32 structHash = keccak256(
            abi.encode(CREDENTIAL_TYPEHASH, _credentialId, _did, _dataHash)
        );

        bytes32 digest = _hashTypedDataV4(structHash);
        address signer = digest.recover(signature);

        require(signer == msg.sender, "Invalid issuer signature");

        credentials[_credentialId] = Credential({
            did: _did,
            issuer: msg.sender,
            dataHash: _dataHash,
            issuedAt: block.timestamp,
            revoked: false
        });

        emit CredentialIssued(_credentialId, _did);
    }

    function revokeCredential(bytes32 _credentialId)
        external
        onlyRole(ISSUER_ROLE)
    {
        require(!credentials[_credentialId].revoked, "Already revoked");

        credentials[_credentialId].revoked = true;

        emit CredentialRevoked(_credentialId);
    }

    function isDIDActive(bytes32 _did)
        external
        view
        returns (bool)
    {
        return dids[_did].active;
    }

    function isCredentialValid(bytes32 _credentialId)
        external
        view
        returns (bool)
    {
        return !credentials[_credentialId].revoked;
    }

    function isAuthorizedKey(bytes32 _did, address _key)
        external
        view
        returns (bool)
    {
        return didKeys[_did][_key];
    }
}