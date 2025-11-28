 //created on 23-06-2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract HealthRecords {
    address public admin;

    constructor() {
        admin = msg.sender;
    }

    struct Record {
        string ipfsHash;
        string recordDescription;
        uint timestamp;
    }

    struct Consultation {
        address doctor;
        string summaryHash;
        uint timestamp;
    }

    mapping(address => bool) public doctors;
    mapping(address => Record[]) public patientRecords;
    mapping(address => Consultation[]) public doctorConsultations;

    modifier onlyDoctorOrPatient() {
        require(doctors[msg.sender] || msg.sender == tx.origin, "Not doctor or patient");
        _;
    }

    modifier onlyDoctor() {
        require(doctors[msg.sender], "Not doctor");
        _;
    }

    function registerDoctor(address _doctor) public {
        require(msg.sender == admin, "Only admin");
        doctors[_doctor] = true;
    }

    function addPatientRecord(
        address patient,
        string memory ipfsHash,
        string memory recordDescription
    ) public onlyDoctorOrPatient {
        Record memory record = Record(ipfsHash, recordDescription, block.timestamp);
        patientRecords[patient].push(record);
    }

    function getPatientRecords(address patient) public view returns (Record[] memory) {
        return patientRecords[patient];
    }

    function addConsultation(
        address doctor,
        address patient,
        string memory consultationSummaryHash
    ) public onlyDoctor {
        Consultation memory consultation = Consultation(doctor, consultationSummaryHash, block.timestamp);
        doctorConsultations[doctor].push(consultation);
    }

    function getConsultationHistory(address doctor) public view returns (Consultation[] memory) {
        return doctorConsultations[doctor];
    }
}
