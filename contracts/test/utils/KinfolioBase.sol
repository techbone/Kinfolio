// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {KinfolioFactory} from "../../src/KinfolioFactory.sol";
import {KinfolioTrust} from "../../src/KinfolioTrust.sol";
import {IKinfolioTrust} from "../../src/interfaces/IKinfolioTrust.sol";
import {MockERC20, MockStockToken} from "../mocks/MockTokens.sol";

/// Shared fixture: one family on production timing.
///   spouse  40% of the portfolio, immediately
///   child   30% at 18, 30% at 25
///   parent  100% of USDG as a 3-year allowance
abstract contract KinfolioBase is Test {
    uint32 internal constant MIN_INACTIVITY = 30 days;
    uint32 internal constant MIN_CHALLENGE = 7 days;
    uint32 internal constant INACTIVITY = 180 days;
    uint32 internal constant CHALLENGE = 14 days;
    uint40 internal constant CHILD_AT_18 = 5 * 365 days;
    uint40 internal constant CHILD_AT_25 = 12 * 365 days;
    uint32 internal constant ALLOWANCE_PERIOD = 3 * 365 days;

    uint256 internal constant TSLA_BALANCE = 100e18;
    uint256 internal constant AMZN_BALANCE = 50e18;
    uint256 internal constant USDG_BALANCE = 120_000e6;

    KinfolioFactory internal factory;
    MockStockToken internal tsla;
    MockStockToken internal amzn;
    MockERC20 internal usdg;

    address internal owner = makeAddr("owner");
    address internal spouse = makeAddr("spouse");
    address internal child = makeAddr("child");
    address internal parent = makeAddr("parent");
    address internal stranger = makeAddr("stranger");

    uint256 internal t0;

    function setUp() public virtual {
        vm.warp(1_790_000_000);
        t0 = block.timestamp;

        usdg = new MockERC20("USDG", 6);
        tsla = new MockStockToken("TSLA");
        amzn = new MockStockToken("AMZN");
        factory = new KinfolioFactory(address(usdg), MIN_INACTIVITY, MIN_CHALLENGE);

        tsla.mint(owner, TSLA_BALANCE);
        amzn.mint(owner, AMZN_BALANCE);
        usdg.mint(owner, USDG_BALANCE);
    }

    // ─── Builders ───────────────────────────────────────────────────────────

    function _assets() internal view returns (address[] memory a) {
        a = new address[](3);
        a[0] = address(tsla);
        a[1] = address(amzn);
        a[2] = address(usdg);
    }

    function _familyGrants() internal view returns (IKinfolioTrust.Grant[] memory g) {
        g = new IKinfolioTrust.Grant[](4);
        g[0] = _grant(spouse, 4000, 0, 0, IKinfolioTrust.Sleeve.Portfolio);
        g[1] = _grant(child, 3000, uint40(t0) + CHILD_AT_18, 0, IKinfolioTrust.Sleeve.Portfolio);
        g[2] = _grant(child, 3000, uint40(t0) + CHILD_AT_25, 0, IKinfolioTrust.Sleeve.Portfolio);
        g[3] = _grant(parent, 10_000, 0, ALLOWANCE_PERIOD, IKinfolioTrust.Sleeve.Cash);
    }

    function _grant(
        address beneficiary,
        uint16 bps,
        uint40 unlockAt,
        uint32 vestDuration,
        IKinfolioTrust.Sleeve sleeve
    ) internal pure returns (IKinfolioTrust.Grant memory) {
        return IKinfolioTrust.Grant(beneficiary, bps, unlockAt, vestDuration, sleeve);
    }

    function _config(address[] memory assets, IKinfolioTrust.Grant[] memory grants)
        internal
        pure
        returns (IKinfolioTrust.TrustConfig memory)
    {
        return IKinfolioTrust.TrustConfig(INACTIVITY, CHALLENGE, assets, grants);
    }

    function _create(IKinfolioTrust.TrustConfig memory config) internal returns (KinfolioTrust) {
        vm.prank(owner);
        return KinfolioTrust(factory.createTrust(config, bytes32(0)));
    }

    /// Family trust with every asset approved in full.
    function _createFamilyTrust() internal returns (KinfolioTrust trust) {
        trust = _create(_config(_assets(), _familyGrants()));
        _approveAll(trust);
    }

    function _approveAll(KinfolioTrust trust) internal {
        vm.startPrank(owner);
        tsla.approve(address(trust), type(uint256).max);
        amzn.approve(address(trust), type(uint256).max);
        usdg.approve(address(trust), type(uint256).max);
        vm.stopPrank();
    }

    // ─── Lifecycle helpers ──────────────────────────────────────────────────

    function _startClaim(KinfolioTrust trust) internal {
        vm.warp(trust.claimableAfter() + 1);
        vm.prank(spouse);
        trust.startClaim();
    }

    function _release(KinfolioTrust trust) internal {
        _startClaim(trust);
        vm.warp(trust.finalizableAfter() + 1);
        trust.finalize();
    }
}
