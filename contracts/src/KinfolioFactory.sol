// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {IKinfolioFactory} from "./interfaces/IKinfolioFactory.sol";
import {IKinfolioTrust} from "./interfaces/IKinfolioTrust.sol";
import {KinfolioTrust} from "./KinfolioTrust.sol";

/// @title KinfolioFactory
/// @notice Deploys one KinfolioTrust clone per family and keeps a lookup index so
/// owners and heirs can find their trusts without an off-chain indexer.
/// @dev No admin, no fees, no upgrade path. Timing minimums are fixed per deployment
/// (short for the testnet demo profile, 30d/7d for production).
contract KinfolioFactory is IKinfolioFactory {
    address public immutable IMPLEMENTATION;

    mapping(address trust => bool) public isTrust;
    mapping(address owner => address[]) private _trustsOf;
    mapping(address beneficiary => address[]) private _trustsFor;
    mapping(address beneficiary => mapping(address trust => bool)) private _indexed;

    // forge-lint: disable-next-line(missing-zero-check)
    constructor(address cashAsset, uint32 minInactivity, uint32 minChallenge) {
        // Zero address and period bounds are validated by the KinfolioTrust constructor.
        IMPLEMENTATION =
            address(new KinfolioTrust(address(this), cashAsset, minInactivity, minChallenge));
    }

    /// @notice Clones and initializes a trust owned by the caller. The address is
    /// derived from (caller, salt), so it can be shown before the transaction lands.
    function createTrust(IKinfolioTrust.TrustConfig calldata config, bytes32 salt)
        external
        returns (address trust)
    {
        trust = Clones.cloneDeterministic(IMPLEMENTATION, _saltFor(msg.sender, salt));
        isTrust[trust] = true;
        _trustsOf[msg.sender].push(trust);
        emit TrustCreated(msg.sender, trust);
        KinfolioTrust(trust).initialize(msg.sender, config);
    }

    function predictTrust(address owner, bytes32 salt) external view returns (address) {
        return Clones.predictDeterministicAddress(IMPLEMENTATION, _saltFor(owner, salt));
    }

    /// @notice Called by trusts whenever beneficiaries are written. Append-only:
    /// an entry may outlive a later grant change, so readers confirm on the trust.
    function indexBeneficiaries(address[] calldata beneficiaries) external {
        if (!isTrust[msg.sender]) revert NotTrust();
        uint256 n = beneficiaries.length;
        for (uint256 i; i < n; ++i) {
            address b = beneficiaries[i];
            if (_indexed[b][msg.sender]) continue;
            _indexed[b][msg.sender] = true;
            _trustsFor[b].push(msg.sender);
            emit BeneficiaryIndexed(b, msg.sender);
        }
    }

    function trustsOf(address owner) external view returns (address[] memory) {
        return _trustsOf[owner];
    }

    function trustsFor(address beneficiary) external view returns (address[] memory) {
        return _trustsFor[beneficiary];
    }

    function _saltFor(address owner, bytes32 salt) private pure returns (bytes32) {
        return keccak256(abi.encode(owner, salt));
    }
}
