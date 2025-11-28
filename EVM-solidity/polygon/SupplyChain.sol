// created on 23-06-2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract SupplyChain {
    address public owner;

    constructor() {
        owner = msg.sender;
    }

    struct BatchHistory {
        string location;
        string status;
        uint timestamp;
    }

    struct Batch {
        string description;
        uint quantity;
        address supplier;
        address hospital;
        bool delivered;
        BatchHistory[] history;
    }

    mapping(string => Batch) public batches;
    mapping(address => bool) public suppliers;
    mapping(address => bool) public hospitals;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    modifier onlySupplier() {
        require(suppliers[msg.sender], "Not supplier");
        _;
    }

    modifier onlyHospital() {
        require(hospitals[msg.sender], "Not hospital");
        _;
    }

    modifier onlySupplierOrHospital() {
        require(suppliers[msg.sender] || hospitals[msg.sender], "Not supplier or hospital");
        _;
    }

    function registerSupplier(address _supplier) public onlyOwner {
        suppliers[_supplier] = true;
    }

    function registerHospital(address _hospital) public onlyOwner {
        hospitals[_hospital] = true;
    }

    function mintSupplyBatch(
        string memory batchID,
        string memory description,
        uint quantity
    ) public onlySupplier {
        require(batches[batchID].quantity == 0, "Batch exists");
        Batch storage batch = batches[batchID];
        batch.description = description;
        batch.quantity = quantity;
        batch.supplier = msg.sender;
        batch.delivered = false;
    }

    function updateBatchLocation(
        string memory batchID,
        string memory location,
        string memory status
    ) public onlySupplierOrHospital {
        require(batches[batchID].quantity > 0, "Batch does not exist");
        Batch storage batch = batches[batchID];
        batch.history.push(BatchHistory(location, status, block.timestamp));
    }

    function confirmDelivery(string memory batchID) public onlyHospital {
        require(batches[batchID].quantity > 0, "Batch does not exist");
        batches[batchID].hospital = msg.sender;
        batches[batchID].delivered = true;
    }

    function viewBatchHistory(string memory batchID) public view returns (BatchHistory[] memory) {
        return batches[batchID].history;
    }
}
