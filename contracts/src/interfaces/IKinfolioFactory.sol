// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IKinfolioTrust} from "./IKinfolioTrust.sol";

/// @title IKinfolioFactory
/// @notice Deploys one trust clone per family and indexes trusts by owner and heir.
interface IKinfolioFactory {
    event TrustCreated(address indexed owner, address indexed trust);
    event BeneficiaryIndexed(address indexed beneficiary, address indexed trust);

    error NotTrust();

    function IMPLEMENTATION() external view returns (address);

    function createTrust(IKinfolioTrust.TrustConfig calldata config, bytes32 salt)
        external
        returns (address trust);

    function predictTrust(address owner, bytes32 salt) external view returns (address);

    function indexBeneficiaries(address[] calldata beneficiaries) external;

    function isTrust(address trust) external view returns (bool);

    function trustsOf(address owner) external view returns (address[] memory);

    function trustsFor(address beneficiary) external view returns (address[] memory);
}
