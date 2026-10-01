// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {KinfolioTrust} from "../../src/KinfolioTrust.sol";
import {IKinfolioTrust} from "../../src/interfaces/IKinfolioTrust.sol";
import {MockERC20, MockStockToken} from "../mocks/MockTokens.sol";
import {KinfolioBase} from "../utils/KinfolioBase.sol";

/// Drives a single family trust through random sequences of owner trading,
/// approvals, time jumps, claims, vetoes, issuer pauses and settlement.
/// Calls that achieve nothing revert on purpose, so `show_metrics` reports
/// how often each path really succeeded (calls - reverts).
contract TrustHandler is Test {
    KinfolioTrust internal immutable trust;
    address internal immutable owner;
    address[] internal assets;
    address[] internal heirs;
    address internal market = makeAddr("market");
    address internal stranger = makeAddr("handlerStranger");

    /// What the owner would hold if the trust had never pulled anything.
    mapping(address asset => uint256) public ownerExpected;

    bool public ghostIllegalTransition;
    bool public ghostEarlyClaim;
    bool public ghostEarlyRelease;

    constructor(
        KinfolioTrust trust_,
        address owner_,
        address[] memory assets_,
        address[] memory heirs_
    ) {
        trust = trust_;
        owner = owner_;
        assets = assets_;
        heirs = heirs_;
        for (uint256 i; i < assets_.length; ++i) {
            ownerExpected[assets_[i]] = IERC20(assets_[i]).balanceOf(owner_);
        }
    }

    // ─── Owner ──────────────────────────────────────────────────────────────

    function ownerCheckIn() external {
        vm.prank(owner);
        trust.checkIn();
    }

    function ownerBuy(uint256 assetSeed, uint256 amount) external {
        address asset = _asset(assetSeed);
        if (_paused(asset)) return;
        amount = bound(amount, 1, 1_000e18);
        MockERC20(asset).mint(owner, amount);
        ownerExpected[asset] += amount;
    }

    function ownerSell(uint256 assetSeed, uint256 amount) external {
        address asset = _asset(assetSeed);
        uint256 balance = IERC20(asset).balanceOf(owner);
        if (balance == 0 || _paused(asset)) return;
        amount = bound(amount, 1, balance);
        vm.prank(owner);
        IERC20(asset).transfer(market, amount);
        ownerExpected[asset] -= amount;
    }

    function ownerApprove(uint256 assetSeed, uint256 amount) external {
        vm.prank(owner);
        IERC20(_asset(assetSeed)).approve(address(trust), amount);
    }

    // ─── Time and issuer ────────────────────────────────────────────────────

    function warp(uint256 secs) external {
        vm.warp(vm.getBlockTimestamp() + bound(secs, 1, 400 days));
    }

    function togglePause(uint256 assetSeed) external {
        address asset = _asset(assetSeed);
        if (asset == assets[2]) return; // cash asset mock has no pause
        MockStockToken(asset).setPaused(!_paused(asset));
    }

    // ─── Heirs and anyone ───────────────────────────────────────────────────

    function startClaim(uint256 heirSeed) external {
        bool wasEligible = block.timestamp > trust.claimableAfter();
        vm.prank(heirs[heirSeed % heirs.length]);
        trust.startClaim();
        if (!wasEligible) ghostEarlyClaim = true;
    }

    function strangerStartsClaim() external {
        vm.prank(stranger);
        try trust.startClaim() {
            ghostIllegalTransition = true;
        } catch {}
    }

    function strangerVetoes() external {
        IKinfolioTrust.State before = trust.state();
        vm.prank(stranger);
        try trust.checkIn() {} catch {}
        if (
            before == IKinfolioTrust.State.Challenge && trust.state() == IKinfolioTrust.State.Active
        ) {
            ghostIllegalTransition = true;
        }
    }

    function finalize() external {
        bool wasEligible = trust.state() == IKinfolioTrust.State.Challenge
            && block.timestamp > trust.finalizableAfter();
        trust.finalize();
        if (!wasEligible) ghostEarlyRelease = true;
    }

    /// Silent owner: jump past each deadline in turn so runs reach settlement
    /// often, while the single-step actions above still interleave vetoes.
    function fastForwardToRelease(uint256 heirSeed) external {
        IKinfolioTrust.State s = trust.state();
        require(s == IKinfolioTrust.State.Active || s == IKinfolioTrust.State.Challenge, "settled");
        if (s == IKinfolioTrust.State.Active) {
            _warpPast(trust.claimableAfter());
            vm.prank(heirs[heirSeed % heirs.length]);
            trust.startClaim();
        }
        _warpPast(trust.finalizableAfter());
        trust.finalize();
    }

    function collect(uint256 assetSeed) external {
        require(trust.collect(_asset(assetSeed)) > 0, "nothing collected");
    }

    function collectAll() external {
        try trust.collectAll() {} catch {}
    }

    function distribute(uint256 grantSeed, uint256 assetSeed) external {
        uint256 grantId = grantSeed % trust.grantCount();
        require(trust.distribute(grantId, _asset(assetSeed)) > 0, "nothing distributed");
    }

    function distributeAll(uint256 grantSeed) external {
        try trust.distributeAll(grantSeed % trust.grantCount()) {} catch {}
    }

    // ─── Helpers ────────────────────────────────────────────────────────────

    /// Forward only: cheatcode warps survive reverts, and chain time never rewinds.
    function _warpPast(uint256 deadline) internal {
        if (vm.getBlockTimestamp() <= deadline) vm.warp(deadline + 1);
    }

    function _asset(uint256 seed) internal view returns (address) {
        return assets[seed % assets.length];
    }

    function _paused(address asset) internal view returns (bool) {
        return asset != assets[2] && MockStockToken(asset).paused();
    }
}

contract KinfolioInvariantTest is KinfolioBase {
    KinfolioTrust internal trust;
    TrustHandler internal handler;
    address[] internal heirs;

    function setUp() public override {
        super.setUp();
        trust = _createFamilyTrust();
        heirs.push(spouse);
        heirs.push(child);
        heirs.push(parent);
        handler = new TrustHandler(trust, owner, _assets(), heirs);
        targetContract(address(handler));
    }

    /// I1 + I2: owner funds move only through the owner's own trades or a
    /// post-release collect, and every collected unit came from the owner.
    function invariant_OwnerFundsMoveOnlyAfterRelease() public view {
        address[] memory assets = _assets();
        bool released = trust.state() == IKinfolioTrust.State.Released;
        for (uint256 a; a < assets.length; ++a) {
            uint256 collected = trust.collected(assets[a]);
            if (!released) assertEq(collected, 0, "collected before release");
            assertEq(
                IERC20(assets[a]).balanceOf(owner) + collected,
                handler.ownerExpected(assets[a]),
                "owner funds left without a trade or collect"
            );
        }
    }

    /// I3 + I4: the trust holds exactly what it collected minus what it paid out,
    /// and heirs hold exactly what was distributed to them.
    function invariant_TrustIsExactlySolvent() public view {
        address[] memory assets = _assets();
        uint256 grants = trust.grantCount();
        for (uint256 a; a < assets.length; ++a) {
            uint256 paid;
            for (uint256 g; g < grants; ++g) {
                paid += trust.distributed(g, assets[a]);
            }
            assertLe(paid, trust.collected(assets[a]), "paid more than collected");
            assertEq(
                IERC20(assets[a]).balanceOf(address(trust)),
                trust.collected(assets[a]) - paid,
                "trust balance mismatch"
            );
            uint256 held;
            for (uint256 h; h < heirs.length; ++h) {
                held += IERC20(assets[a]).balanceOf(heirs[h]);
            }
            assertEq(held, paid, "heirs received tokens outside distribute");
        }
    }

    /// I5: no grant is ever paid beyond its vested entitlement.
    function invariant_PayoutsWithinVestedEntitlement() public view {
        address[] memory assets = _assets();
        uint256 grants = trust.grantCount();
        for (uint256 g; g < grants; ++g) {
            for (uint256 a; a < assets.length; ++a) {
                uint256 paid = trust.distributed(g, assets[a]);
                assertLe(paid, trust.vested(g, assets[a]), "paid beyond vested");
                assertLe(paid, trust.entitlement(g, assets[a]), "paid beyond entitlement");
            }
        }
    }

    /// I6: only the owner reverts a claim, and only time completes one.
    function invariant_NoIllegalTransitions() public view {
        assertFalse(handler.ghostIllegalTransition(), "non-owner moved the state machine");
        assertFalse(handler.ghostEarlyClaim(), "claim before inactivity deadline");
        assertFalse(handler.ghostEarlyRelease(), "release before challenge window");
    }

    function invariant_StateFieldsConsistent() public view {
        IKinfolioTrust.State s = trust.state();
        if (s == IKinfolioTrust.State.Active) {
            assertEq(trust.claimant(), address(0));
            assertEq(trust.releasedAt(), 0);
        } else if (s == IKinfolioTrust.State.Released) {
            assertGt(trust.releasedAt(), trust.finalizableAfter());
        }
    }
}
