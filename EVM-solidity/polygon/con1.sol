// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract ProjectLogger {
    address public admin;

    constructor() {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "Only admin can perform this.");
        _;
    }

    modifier onlyOfficial() {
        require(isOfficial[msg.sender], "Only approved officials can perform this.");
        _;
    }

    struct Project {
        uint projectId;
        string projectHash; // Off-chain metadata hash
        uint timestamp;
    }

    struct Update {
        uint projectId;
        string updateHash; // Off-chain update hash
        address uploadedBy;
        bool verified;
        uint timestamp;
    }

    mapping(uint => Project) public projects;
    mapping(uint => Update[]) public projectUpdates;
    mapping(address => bool) public isOfficial;

    event ProjectMinted(uint projectId, string projectHash, uint timestamp);
    event UpdateLogged(uint projectId, string updateHash, address official, uint timestamp);
    event UpdateVerified(uint projectId, string updateHash, address verifier, uint timestamp);

    function mintProject(uint projectId, string calldata projectHash) external onlyAdmin {
        projects[projectId] = Project(projectId, projectHash, block.timestamp);
        emit ProjectMinted(projectId, projectHash, block.timestamp);
    }

    function logUpdate(uint projectId, string calldata updateHash) external onlyOfficial {
        Update memory newUpdate = Update(projectId, updateHash, msg.sender, false, block.timestamp);
        projectUpdates[projectId].push(newUpdate);
        emit UpdateLogged(projectId, updateHash, msg.sender, block.timestamp);
    }

    function verifyUpdate(uint projectId, uint updateIndex) external onlyAdmin {
        Update storage upd = projectUpdates[projectId][updateIndex];
        require(!upd.verified, "Already verified.");
        upd.verified = true;
        emit UpdateVerified(projectId, upd.updateHash, msg.sender, block.timestamp);
    }

    function addOfficial(address official) external onlyAdmin {
        isOfficial[official] = true;
    }

    function removeOfficial(address official) external onlyAdmin {
        isOfficial[official] = false;
    }
}
