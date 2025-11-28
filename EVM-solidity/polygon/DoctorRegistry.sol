//created on 23-06-2025
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract DoctorRegistry {
    address public admin;

    constructor() {
        admin = msg.sender;
    }

    struct DoctorProfile {
        string name;
        string specialty;
        string credentialURI;
        uint totalRating;
        uint numRatings;
    }

    mapping(address => DoctorProfile) public doctorProfiles;
    mapping(address => mapping(address => bool)) public hasRated; // patient → doctor → rated?
    address[] public doctorAddresses; // ⭐️ to track all doctors

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier onlyPatient() {
        require(msg.sender == tx.origin, "Only patients");
        _;
    }

    function registerDoctor(address doctor, string memory name, string memory specialty) public onlyAdmin {
        doctorProfiles[doctor] = DoctorProfile(name, specialty, "", 0, 0);
        doctorAddresses.push(doctor); // ⭐️ Track doctor address
    }

    function mintCredentialNFT(address doctor, string memory metadataURI) public onlyAdmin {
        doctorProfiles[doctor].credentialURI = metadataURI;
    }

    function getDoctorProfile(address doctor) public view returns (DoctorProfile memory) {
        return doctorProfiles[doctor];
    }

    function rateDoctor(address doctor, uint rating, string memory review) public onlyPatient {
        require(rating >= 1 && rating <= 5, "Rating out of range");
        require(!hasRated[msg.sender][doctor], "Already rated");
        
        doctorProfiles[doctor].totalRating += rating;
        doctorProfiles[doctor].numRatings += 1;
        hasRated[msg.sender][doctor] = true;
    }

    function getTopDoctors() public view returns (DoctorProfile[] memory) {
        uint count = doctorAddresses.length;
        DoctorProfile[] memory topDoctors = new DoctorProfile[](count);

        for (uint i = 0; i < count; i++) {
            address doctorAddr = doctorAddresses[i];
            topDoctors[i] = doctorProfiles[doctorAddr];
        }

        return topDoctors; 
    }
}
