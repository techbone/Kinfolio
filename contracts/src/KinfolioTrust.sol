// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IKinfolioTrust} from "./interfaces/IKinfolioTrust.sol";
import {IKinfolioFactory} from "./interfaces/IKinfolioFactory.sol";
import {Vesting} from "./libraries/Vesting.sol";

/// @title KinfolioTrust
/// @notice A non-custodial family trust for an ERC-20 portfolio (stock tokens and USDG).
/// Assets stay in the owner's wallet. The trust only holds an allowance, and it can
/// use that allowance only after the owner has been silent for `inactivityPeriod`
/// and a beneficiary's claim has survived `challengeWindow` without a veto.
/// @dev Deployed once as an implementation; every family gets its own EIP-1167 clone,
/// so approvals are never shared across families. There is no admin role.
/// All accounting is in raw token units: ERC-8056 multiplier changes (splits,
/// reinvested dividends) never touch balances, so heirs' tranches track them for free.
contract KinfolioTrust is IKinfolioTrust, Initializable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant MAX_ASSETS = 16;
    uint256 public constant MAX_GRANTS = 12;
    uint256 public constant FULL_BPS = 10_000;
    uint32 public constant MAX_INACTIVITY = 10 * 365 days;
    uint32 public constant MAX_CHALLENGE = 365 days;
    uint32 public constant MAX_VEST_DURATION = 50 * 365 days;
    uint256 public constant MAX_UNLOCK_DELAY = 100 * 365 days;

    /// Shared by every clone (immutables live in the implementation's code).
    address public immutable FACTORY;
    address public immutable CASH_ASSET;
    uint32 public immutable MIN_INACTIVITY;
    uint32 public immutable MIN_CHALLENGE;

    address public owner;
    State public state;
    uint32 public inactivityPeriod;
    uint32 public challengeWindow;
    uint40 public lastCheckIn;
    uint40 public claimStartedAt;
    uint40 public releasedAt;
    address public claimant;
    bool public hasCashSleeve;

    address[] private _assets;
    Grant[] private _grants;
    mapping(address asset => bool) public isAsset;
    /// Raw units received from the owner, measured as the trust's balance delta.
    mapping(address asset => uint256) public collected;
    /// Raw units already sent to each grant's beneficiary.
    mapping(uint256 grantId => mapping(address asset => uint256)) public distributed;

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier inState(State expected) {
        if (state != expected) revert InvalidState(state);
        _;
    }

    constructor(address factory, address cashAsset, uint32 minInactivity, uint32 minChallenge) {
        if (factory == address(0) || cashAsset == address(0)) revert ZeroAddress();
        if (
            minInactivity == 0 || minChallenge == 0 || minInactivity > MAX_INACTIVITY
                || minChallenge > MAX_CHALLENGE
        ) revert InvalidPeriods();
        FACTORY = factory;
        CASH_ASSET = cashAsset;
        MIN_INACTIVITY = minInactivity;
        MIN_CHALLENGE = minChallenge;
        _disableInitializers();
    }

    /// @notice Called once by the factory in the same transaction that clones the trust.
    function initialize(address owner_, TrustConfig calldata config) external initializer {
        if (msg.sender != FACTORY) revert NotFactory();
        if (owner_ == address(0)) revert ZeroAddress();
        owner = owner_;
        _setPeriods(config.inactivityPeriod, config.challengeWindow);
        _setAssets(config.assets);
        _setGrants(config.grants);
        _checkIn();
        emit TrustInitialized(owner_, config.inactivityPeriod, config.challengeWindow);
    }

    // ─── Owner ──────────────────────────────────────────────────────────────

    /// @notice Proof of life. During a Challenge this is the veto.
    function checkIn() external onlyOwner {
        State s = state;
        if (s == State.Challenge) {
            address vetoed = claimant;
            state = State.Active;
            claimant = address(0);
            claimStartedAt = 0;
            emit ClaimVetoed(vetoed);
        } else if (s != State.Active) {
            revert InvalidState(s);
        }
        _checkIn();
    }

    function setPeriods(uint32 inactivity, uint32 challenge)
        external
        onlyOwner
        inState(State.Active)
    {
        _setPeriods(inactivity, challenge);
        _checkIn();
    }

    function setAssets(address[] calldata assets) external onlyOwner inState(State.Active) {
        _setAssets(assets);
        if (hasCashSleeve && !isAsset[CASH_ASSET]) revert CashSleeveNeedsCashAsset();
        _checkIn();
    }

    function setGrants(Grant[] calldata grants) external onlyOwner inState(State.Active) {
        _setGrants(grants);
        _checkIn();
    }

    /// @notice Permanently retires the trust. A closed trust can never pull funds.
    function close() external onlyOwner inState(State.Active) {
        state = State.Closed;
        emit TrustClosed();
    }

    /// @notice Returns tokens sent to the trust by mistake. Unavailable once a claim
    /// has started, so it can never reach funds collected for heirs.
    function rescue(address token) external nonReentrant onlyOwner {
        State s = state;
        if (s != State.Active && s != State.Closed) revert InvalidState(s);
        if (s == State.Active) _checkIn();
        uint256 amount = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransfer(msg.sender, amount);
        emit Rescued(token, amount);
    }

    // ─── Inheritance path ───────────────────────────────────────────────────

    /// @notice Any beneficiary can open a claim once the owner has been silent
    /// for longer than `inactivityPeriod`.
    function startClaim() external inState(State.Active) {
        if (!_isBeneficiary(msg.sender)) revert NotBeneficiary();
        uint256 deadline = claimableAfter();
        if (block.timestamp <= deadline) revert OwnerStillActive(deadline);
        state = State.Challenge;
        claimant = msg.sender;
        claimStartedAt = SafeCast.toUint40(block.timestamp);
        emit ClaimStarted(msg.sender, block.timestamp + challengeWindow);
    }

    /// @notice Anyone can finalize once the challenge window has passed unvetoed.
    function finalize() external inState(State.Challenge) {
        uint256 deadline = finalizableAfter();
        if (block.timestamp <= deadline) revert ChallengeWindowOpen(deadline);
        state = State.Released;
        releasedAt = SafeCast.toUint40(block.timestamp);
        emit Finalized(block.timestamp);
    }

    /// @notice Pulls `min(balance, allowance)` of a covered asset from the owner.
    /// Repeatable, so assets that reach the owner's wallet later are still covered.
    function collect(address asset)
        public
        nonReentrant
        inState(State.Released)
        returns (uint256 received)
    {
        if (!isAsset[asset]) revert UnknownAsset(asset);
        IERC20 token = IERC20(asset);
        address from = owner;
        uint256 amount = Math.min(token.balanceOf(from), token.allowance(from, address(this)));
        if (amount == 0) return 0;

        uint256 balanceBefore = token.balanceOf(address(this));
        // `from` is always the owner, and only after release (invariants I1, I2).
        // forge-lint: disable-next-line(arbitrary-send-erc20)
        token.safeTransferFrom(from, address(this), amount);
        received = token.balanceOf(address(this)) - balanceBefore;

        collected[asset] += received;
        emit Collected(asset, received);
    }

    /// @notice Collects every covered asset. One failing asset (e.g. an issuer
    /// pause) is skipped and can be retried; it never blocks the others.
    function collectAll() external inState(State.Released) {
        uint256 n = _assets.length;
        for (uint256 i; i < n; ++i) {
            address asset = _assets[i];
            try this.collect(asset) {}
            catch {
                emit CollectFailed(asset);
            }
        }
    }

    /// @notice Sends a grant's vested, undistributed share of `asset` to its
    /// stored beneficiary. Callable by anyone; the destination is never an input.
    function distribute(uint256 grantId, address asset)
        public
        nonReentrant
        inState(State.Released)
        returns (uint256 amount)
    {
        Grant memory g = _grantAt(grantId);
        amount = _claimable(g, grantId, asset);
        if (amount == 0) return 0;

        distributed[grantId][asset] += amount;
        emit Distributed(grantId, g.beneficiary, asset, amount);
        IERC20(asset).safeTransfer(g.beneficiary, amount);
    }

    /// @notice Distributes every asset for one grant, isolating per-asset failures.
    function distributeAll(uint256 grantId) external inState(State.Released) {
        _grantAt(grantId);
        uint256 n = _assets.length;
        for (uint256 i; i < n; ++i) {
            address asset = _assets[i];
            try this.distribute(grantId, asset) {}
            catch {
                emit DistributeFailed(grantId, asset);
            }
        }
    }

    /// @notice Lets an heir move their own grant to a new wallet (lost key, blocked
    /// address) without the owner. Only after release, only by that beneficiary.
    function transferGrant(uint256 grantId, address to) external inState(State.Released) {
        if (grantId >= _grants.length) revert GrantNotFound(grantId);
        Grant storage g = _grants[grantId];
        if (msg.sender != g.beneficiary) revert NotBeneficiary();
        if (to == address(0) || to == address(this) || to == owner) revert InvalidBeneficiary(to);
        g.beneficiary = to;
        emit GrantTransferred(grantId, msg.sender, to);

        address[] memory list = new address[](1);
        list[0] = to;
        IKinfolioFactory(FACTORY).indexBeneficiaries(list);
    }

    // ─── Views ──────────────────────────────────────────────────────────────

    function claimableAfter() public view returns (uint256) {
        return uint256(lastCheckIn) + inactivityPeriod;
    }

    /// @dev Meaningful only while in Challenge.
    function finalizableAfter() public view returns (uint256) {
        return uint256(claimStartedAt) + challengeWindow;
    }

    function sleeveOf(address asset) public view returns (Sleeve) {
        return asset == CASH_ASSET && hasCashSleeve ? Sleeve.Cash : Sleeve.Portfolio;
    }

    /// @notice Total raw units this grant is entitled to from what has been collected.
    function entitlement(uint256 grantId, address asset) external view returns (uint256) {
        return _entitlement(_grantAt(grantId), asset);
    }

    function vested(uint256 grantId, address asset) external view returns (uint256) {
        return _vested(_grantAt(grantId), asset);
    }

    function claimable(uint256 grantId, address asset) external view returns (uint256) {
        return _claimable(_grantAt(grantId), grantId, asset);
    }

    /// @notice How much of `asset` the trust could pull today: min(balance, allowance).
    function coverage(address asset) external view returns (uint256) {
        IERC20 token = IERC20(asset);
        return Math.min(token.balanceOf(owner), token.allowance(owner, address(this)));
    }

    function getAssets() external view returns (address[] memory) {
        return _assets;
    }

    function getGrants() external view returns (Grant[] memory) {
        return _grants;
    }

    function grantCount() external view returns (uint256) {
        return _grants.length;
    }

    function getTrust() external view returns (TrustView memory) {
        return TrustView({
            owner: owner,
            state: state,
            inactivityPeriod: inactivityPeriod,
            challengeWindow: challengeWindow,
            lastCheckIn: lastCheckIn,
            claimStartedAt: claimStartedAt,
            releasedAt: releasedAt,
            claimant: claimant,
            hasCashSleeve: hasCashSleeve,
            cashAsset: CASH_ASSET,
            assets: _assets,
            grants: _grants
        });
    }

    // ─── Internal ───────────────────────────────────────────────────────────

    function _checkIn() private {
        lastCheckIn = SafeCast.toUint40(block.timestamp);
        emit CheckedIn(block.timestamp);
    }

    function _setPeriods(uint32 inactivity, uint32 challenge) private {
        if (
            inactivity < MIN_INACTIVITY || inactivity > MAX_INACTIVITY || challenge < MIN_CHALLENGE
                || challenge > MAX_CHALLENGE
        ) revert InvalidPeriods();
        inactivityPeriod = inactivity;
        challengeWindow = challenge;
        emit PeriodsUpdated(inactivity, challenge);
    }

    function _setAssets(address[] calldata assets) private {
        uint256 n = assets.length;
        if (n == 0 || n > MAX_ASSETS) revert InvalidAssetCount();

        uint256 previous = _assets.length;
        for (uint256 i; i < previous; ++i) {
            isAsset[_assets[i]] = false;
        }
        delete _assets;

        for (uint256 i; i < n; ++i) {
            address asset = assets[i];
            if (asset == address(0) || asset == address(this) || asset.code.length == 0) {
                revert InvalidAsset(asset);
            }
            if (isAsset[asset]) revert DuplicateAsset(asset);
            isAsset[asset] = true;
            _assets.push(asset);
        }
        emit AssetsUpdated(assets);
    }

    function _setGrants(Grant[] calldata grants) private {
        uint256 n = grants.length;
        if (n == 0 || n > MAX_GRANTS) revert InvalidGrantCount();

        address owner_ = owner;
        uint256 latestUnlock = block.timestamp + MAX_UNLOCK_DELAY;
        uint256 portfolioBps = 0;
        uint256 cashBps = 0;
        address[] memory beneficiaries = new address[](n);

        delete _grants;
        for (uint256 i; i < n; ++i) {
            Grant calldata g = grants[i];
            address b = g.beneficiary;
            if (b == address(0) || b == owner_ || b == address(this)) revert InvalidBeneficiary(b);
            if (g.bps == 0) revert ZeroShare(i);
            if (g.unlockAt > latestUnlock || g.vestDuration > MAX_VEST_DURATION) {
                revert InvalidSchedule(i);
            }
            if (g.sleeve == Sleeve.Cash) cashBps += g.bps;
            else portfolioBps += g.bps;

            _grants.push(g);
            beneficiaries[i] = b;
        }

        if (portfolioBps != FULL_BPS) revert SharesMustTotal100(Sleeve.Portfolio, portfolioBps);
        if (cashBps != 0) {
            if (cashBps != FULL_BPS) revert SharesMustTotal100(Sleeve.Cash, cashBps);
            if (!isAsset[CASH_ASSET]) revert CashSleeveNeedsCashAsset();
        }
        hasCashSleeve = cashBps != 0;

        emit GrantsUpdated(grants);
        IKinfolioFactory(FACTORY).indexBeneficiaries(beneficiaries);
    }

    function _isBeneficiary(address account) private view returns (bool) {
        uint256 n = _grants.length;
        for (uint256 i; i < n; ++i) {
            if (_grants[i].beneficiary == account) return true;
        }
        return false;
    }

    function _grantAt(uint256 grantId) private view returns (Grant memory) {
        if (grantId >= _grants.length) revert GrantNotFound(grantId);
        return _grants[grantId];
    }

    function _entitlement(Grant memory g, address asset) private view returns (uint256) {
        if (sleeveOf(asset) != g.sleeve) return 0;
        return Math.mulDiv(collected[asset], g.bps, FULL_BPS);
    }

    function _vested(Grant memory g, address asset) private view returns (uint256) {
        if (state != State.Released) return 0;
        uint256 start = Math.max(releasedAt, g.unlockAt);
        return Vesting.vested(_entitlement(g, asset), start, g.vestDuration, block.timestamp);
    }

    function _claimable(Grant memory g, uint256 grantId, address asset)
        private
        view
        returns (uint256)
    {
        uint256 v = _vested(g, asset);
        uint256 d = distributed[grantId][asset];
        return v > d ? v - d : 0;
    }
}
