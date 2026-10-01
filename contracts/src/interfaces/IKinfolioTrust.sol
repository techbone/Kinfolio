// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IKinfolioTrust
/// @notice Types, events and errors for a Kinfolio family trust.
interface IKinfolioTrust {
    /// Active → Challenge → Released is the inheritance path. The owner can veto
    /// (Challenge → Active) or close (Active → Closed) at any time while alive.
    enum State {
        Active,
        Challenge,
        Released,
        Closed
    }

    /// Portfolio: every covered asset except the cash asset (and the cash asset
    /// too when no Cash grants exist). Cash: the cash asset (USDG) only.
    enum Sleeve {
        Portfolio,
        Cash
    }

    /// One tranche of the trust. A beneficiary may hold several grants.
    struct Grant {
        address beneficiary;
        uint16 bps; // share of the sleeve, out of 10_000
        uint40 unlockAt; // vesting cannot start before this (0 = at release)
        uint32 vestDuration; // 0 = lump sum, else linear over this many seconds
        Sleeve sleeve;
    }

    struct TrustConfig {
        uint32 inactivityPeriod;
        uint32 challengeWindow;
        address[] assets;
        Grant[] grants;
    }

    struct TrustView {
        address owner;
        State state;
        uint32 inactivityPeriod;
        uint32 challengeWindow;
        uint40 lastCheckIn;
        uint40 claimStartedAt;
        uint40 releasedAt;
        address claimant;
        bool hasCashSleeve;
        address cashAsset;
        address[] assets;
        Grant[] grants;
    }

    event TrustInitialized(address indexed owner, uint32 inactivityPeriod, uint32 challengeWindow);
    event CheckedIn(uint256 at);
    event PeriodsUpdated(uint32 inactivityPeriod, uint32 challengeWindow);
    event AssetsUpdated(address[] assets);
    event GrantsUpdated(Grant[] grants);
    event ClaimStarted(address indexed claimant, uint256 finalizableAfter);
    event ClaimVetoed(address indexed claimant);
    event Finalized(uint256 releasedAt);
    event Collected(address indexed asset, uint256 amount);
    event CollectFailed(address indexed asset);
    event Distributed(
        uint256 indexed grantId, address indexed beneficiary, address indexed asset, uint256 amount
    );
    event DistributeFailed(uint256 indexed grantId, address indexed asset);
    event GrantTransferred(uint256 indexed grantId, address indexed from, address indexed to);
    event TrustClosed();
    event Rescued(address indexed token, uint256 amount);

    error NotFactory();
    error NotOwner();
    error NotBeneficiary();
    error ZeroAddress();
    error InvalidState(State current);
    error OwnerStillActive(uint256 claimableAfter);
    error ChallengeWindowOpen(uint256 finalizableAfter);
    error InvalidPeriods();
    error InvalidAssetCount();
    error InvalidAsset(address asset);
    error DuplicateAsset(address asset);
    error UnknownAsset(address asset);
    error InvalidGrantCount();
    error InvalidBeneficiary(address beneficiary);
    error ZeroShare(uint256 index);
    error InvalidSchedule(uint256 index);
    error SharesMustTotal100(Sleeve sleeve, uint256 bps);
    error CashSleeveNeedsCashAsset();
    error GrantNotFound(uint256 grantId);
    error InvalidConfig();
}
