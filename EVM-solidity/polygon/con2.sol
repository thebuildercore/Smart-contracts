// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract ProjectTracker {

    // ─── STRUCTS ────────────────────────────────────────────────
    struct Project {
        string ipfsHash; // IPFS CID for initial project data
        address assignedOfficial;
        bool isVerified;
        address beneficiary;
        uint256 assignTime;
        bool beneficiaryAcknowledged;
        uint256 usedFunds;
    }

    struct Update {
        string ipfsHash; // IPFS CID for update
        bool verified;
    }

    // ─── ROLE MAPPINGS ──────────────────────────────────────────
    // beneficiary is for, employee verification of fund received

    mapping(address => bool) public isAdmin;
    mapping(address => bool) public isOfficial;

    // ─── DATA STORAGE ───────────────────────────────────────────
    mapping(uint256 => Project) public projects;
    mapping(uint256 => Update[]) public projectUpdates;
    uint256 public projectCounter;

    // ─── MODIFIERS ──────────────────────────────────────────────
    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "Not an admin");
        _;
    }

    modifier onlyOfficial() {
        require(isOfficial[msg.sender], "Not an approved official");
        _;
    }

    modifier onlyBeneficiary(uint256 projectId) {
        require(msg.sender == projects[projectId].beneficiary, "Not the beneficiary");
        _;
    }

    // ─── CONSTRUCTOR ────────────────────────────────────────────
    constructor() {
        isAdmin[msg.sender] = true; // Deployer becomes the first admin
    }

    // ─── EVENTS ─────────────────────────────────────────────────
    event AdminAdded(address indexed admin);
    event AdminRemoved(address indexed admin);
    event OfficialAssigned(address indexed official);
    event OfficialRemoved(address indexed official);

    // ─── ADMIN FUNCTIONS ────────────────────────────────────────

    function addAdmin(address _admin) external onlyAdmin {
        isAdmin[_admin] = true;
        emit AdminAdded(_admin);
    }

    function removeAdmin(address _admin) external onlyAdmin {
        require(_admin != msg.sender, "You cannot remove yourself");
        isAdmin[_admin] = false;
        emit AdminRemoved(_admin);
    }
// make sure admin dont remove itself 

    function assignOfficial(address _official) external onlyAdmin {
        isOfficial[_official] = true;
        emit OfficialAssigned(_official);
    }

    function removeOfficial(address _official) external onlyAdmin {
        isOfficial[_official] = false;
        emit OfficialRemoved(_official);
    }

    // ─── PROJECT FLOW ───────────────────────────────────────────

    function createProject(
        string memory _ipfsHash,
        address _official,
        address _beneficiary
    ) external onlyAdmin {
        require(isOfficial[_official], "Official must be approved");

        projects[projectCounter] = Project({
            ipfsHash: _ipfsHash,
            assignedOfficial: _official,
            isVerified: false,
            beneficiary: _beneficiary,
            assignTime: block.timestamp,
            beneficiaryAcknowledged: false,
            usedFunds: 0
        });

        projectCounter++;
    }

    function acknowledgeFund(uint256 _projectId) external onlyBeneficiary(_projectId) {
        require(
            block.timestamp <= projects[_projectId].assignTime + 7 days,
            "Acknowledgment window passed"
        );
        projects[_projectId].beneficiaryAcknowledged = true;
    }

    function updateFundsUsed(uint256 _projectId, uint256 _amount) external onlyOfficial {
        require(projects[_projectId].assignedOfficial == msg.sender, "Not assigned to this project");
        projects[_projectId].usedFunds += _amount;
    }

    function submitUpdate(uint256 _projectId, string memory _ipfsHash) external onlyOfficial {
        require(projects[_projectId].assignedOfficial == msg.sender, "Not assigned to this project");
        projectUpdates[_projectId].push(Update({
            ipfsHash: _ipfsHash,
            verified: false
        }));
    }

    function verifyUpdate(uint256 _projectId, uint256 _updateIndex) external onlyAdmin {
        projectUpdates[_projectId][_updateIndex].verified = true;
    }

    // ─── VIEW FUNCTIONS ─────────────────────────────────────────

    function getProjectUpdates(uint256 _projectId) external view returns (Update[] memory) {
        return projectUpdates[_projectId];
    }

    function getProject(uint256 _projectId) external view returns (Project memory) {
        return projects[_projectId];
    }
}
