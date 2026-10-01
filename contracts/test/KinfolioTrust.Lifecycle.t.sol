// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {KinfolioTrust} from "../src/KinfolioTrust.sol";
import {IKinfolioTrust} from "../src/interfaces/IKinfolioTrust.sol";
import {KinfolioBase} from "./utils/KinfolioBase.sol";

/// State machine, access control, timing boundaries and owner configuration.
contract KinfolioTrustLifecycleTest is KinfolioBase {
    KinfolioTrust internal trust;

    function setUp() public override {
        super.setUp();
        trust = _createFamilyTrust();
    }

    // ─── Creation ───────────────────────────────────────────────────────────

    function test_Create_StoresConfig() public view {
        IKinfolioTrust.TrustView memory v = trust.getTrust();
        assertEq(v.owner, owner);
        assertEq(uint8(v.state), uint8(IKinfolioTrust.State.Active));
        assertEq(v.inactivityPeriod, INACTIVITY);
        assertEq(v.challengeWindow, CHALLENGE);
        assertEq(v.lastCheckIn, t0);
        assertEq(v.assets.length, 3);
        assertEq(v.grants.length, 4);
        assertEq(v.grants[1].unlockAt, t0 + CHILD_AT_18);
        assertTrue(v.hasCashSleeve);
        assertEq(v.cashAsset, address(usdg));
        assertTrue(trust.isAsset(address(tsla)));
        assertEq(uint8(trust.sleeveOf(address(usdg))), uint8(IKinfolioTrust.Sleeve.Cash));
        assertEq(uint8(trust.sleeveOf(address(tsla))), uint8(IKinfolioTrust.Sleeve.Portfolio));
    }

    function test_Create_HoldsNothing() public view {
        assertEq(tsla.balanceOf(address(trust)), 0);
        assertEq(tsla.balanceOf(owner), TSLA_BALANCE);
        assertEq(trust.coverage(address(tsla)), TSLA_BALANCE);
    }

    function test_Views_NothingVestsBeforeRelease() public {
        _startClaim(trust);
        vm.warp(t0 + 20 * 365 days);
        assertEq(trust.vested(0, address(tsla)), 0);
        assertEq(trust.claimable(0, address(tsla)), 0);
    }

    // ─── Check-in and claim timing ──────────────────────────────────────────

    function test_CheckIn_ResetsDeadline() public {
        vm.warp(t0 + 100 days);
        vm.prank(owner);
        trust.checkIn();
        assertEq(trust.lastCheckIn(), t0 + 100 days);
        assertEq(trust.claimableAfter(), t0 + 100 days + INACTIVITY);
    }

    function test_RevertWhen_NonOwnerChecksIn() public {
        vm.prank(spouse);
        vm.expectRevert(IKinfolioTrust.NotOwner.selector);
        trust.checkIn();
    }

    function test_StartClaim_BoundaryIsStrict() public {
        uint256 deadline = t0 + INACTIVITY;
        vm.warp(deadline);
        vm.prank(spouse);
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.OwnerStillActive.selector, deadline));
        trust.startClaim();

        vm.warp(deadline + 1);
        vm.expectEmit(true, false, false, true, address(trust));
        emit IKinfolioTrust.ClaimStarted(spouse, deadline + 1 + CHALLENGE);
        vm.prank(spouse);
        trust.startClaim();

        assertEq(uint8(trust.state()), uint8(IKinfolioTrust.State.Challenge));
        assertEq(trust.claimant(), spouse);
        assertEq(trust.claimStartedAt(), deadline + 1);
    }

    function test_RevertWhen_StrangerStartsClaim() public {
        vm.warp(trust.claimableAfter() + 1);
        vm.prank(stranger);
        vm.expectRevert(IKinfolioTrust.NotBeneficiary.selector);
        trust.startClaim();
    }

    function test_AnyBeneficiaryCanStartClaim() public {
        vm.warp(trust.claimableAfter() + 1);
        vm.prank(parent);
        trust.startClaim();
        assertEq(trust.claimant(), parent);
    }

    // ─── Veto ───────────────────────────────────────────────────────────────

    function test_CheckIn_VetoesClaim() public {
        _startClaim(trust);
        uint256 vetoAt = trust.claimStartedAt() + 3 days;
        vm.warp(vetoAt);

        vm.expectEmit(true, false, false, false, address(trust));
        emit IKinfolioTrust.ClaimVetoed(spouse);
        vm.prank(owner);
        trust.checkIn();

        assertEq(uint8(trust.state()), uint8(IKinfolioTrust.State.Active));
        assertEq(trust.claimant(), address(0));
        assertEq(trust.claimStartedAt(), 0);
        assertEq(trust.lastCheckIn(), vetoAt);
    }

    function test_Veto_RestartsInactivityClock() public {
        _startClaim(trust);
        vm.prank(owner);
        trust.checkIn();

        vm.prank(spouse);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.OwnerStillActive.selector, block.timestamp + INACTIVITY
            )
        );
        trust.startClaim();
    }

    function test_RevertWhen_BeneficiaryTriesToVeto() public {
        _startClaim(trust);
        vm.prank(child);
        vm.expectRevert(IKinfolioTrust.NotOwner.selector);
        trust.checkIn();
    }

    // ─── Finalize ───────────────────────────────────────────────────────────

    function test_Finalize_BoundaryIsStrict() public {
        _startClaim(trust);
        uint256 deadline = trust.finalizableAfter();

        vm.warp(deadline);
        vm.expectRevert(
            abi.encodeWithSelector(IKinfolioTrust.ChallengeWindowOpen.selector, deadline)
        );
        trust.finalize();

        vm.warp(deadline + 1);
        vm.prank(stranger); // permissionless
        trust.finalize();
        assertEq(uint8(trust.state()), uint8(IKinfolioTrust.State.Released));
        assertEq(trust.releasedAt(), deadline + 1);
    }

    function test_RevertWhen_FinalizingWithoutClaim() public {
        vm.warp(t0 + 10 * 365 days);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Active
            )
        );
        trust.finalize();
    }

    function test_RevertWhen_OwnerChecksInAfterRelease() public {
        _release(trust);
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Released
            )
        );
        trust.checkIn();
    }

    // ─── Owner configuration is frozen outside Active ───────────────────────

    function test_RevertWhen_EditingDuringChallenge() public {
        _startClaim(trust);
        bytes memory err = abi.encodeWithSelector(
            IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Challenge
        );
        IKinfolioTrust.Grant[] memory grants = _familyGrants();
        address[] memory assets = _assets();

        vm.startPrank(owner);
        vm.expectRevert(err);
        trust.setGrants(grants);
        vm.expectRevert(err);
        trust.setAssets(assets);
        vm.expectRevert(err);
        trust.setPeriods(INACTIVITY, CHALLENGE);
        vm.expectRevert(err);
        trust.close();
        vm.expectRevert(err);
        trust.rescue(address(tsla));
        vm.stopPrank();
    }

    function test_RevertWhen_EditingAfterRelease() public {
        _release(trust);
        IKinfolioTrust.Grant[] memory grants = _familyGrants();
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Released
            )
        );
        trust.setGrants(grants);
    }

    function test_EveryOwnerEditIsProofOfLife() public {
        vm.warp(t0 + 50 days);
        vm.prank(owner);
        trust.setPeriods(INACTIVITY * 2, CHALLENGE);
        assertEq(trust.lastCheckIn(), t0 + 50 days);

        vm.warp(t0 + 60 days);
        vm.prank(owner);
        trust.setGrants(_familyGrants());
        assertEq(trust.lastCheckIn(), t0 + 60 days);

        vm.warp(t0 + 70 days);
        vm.prank(owner);
        trust.setAssets(_assets());
        assertEq(trust.lastCheckIn(), t0 + 70 days);
    }

    function test_RevertWhen_NonOwnerEdits() public {
        IKinfolioTrust.Grant[] memory grants = _familyGrants();
        address[] memory assets = _assets();
        vm.startPrank(spouse);
        vm.expectRevert(IKinfolioTrust.NotOwner.selector);
        trust.setGrants(grants);
        vm.expectRevert(IKinfolioTrust.NotOwner.selector);
        trust.setAssets(assets);
        vm.expectRevert(IKinfolioTrust.NotOwner.selector);
        trust.setPeriods(INACTIVITY, CHALLENGE);
        vm.expectRevert(IKinfolioTrust.NotOwner.selector);
        trust.close();
        vm.expectRevert(IKinfolioTrust.NotOwner.selector);
        trust.rescue(address(tsla));
        vm.stopPrank();
    }

    // ─── Close and rescue ───────────────────────────────────────────────────

    function test_Close_IsTerminal() public {
        vm.prank(owner);
        trust.close();
        assertEq(uint8(trust.state()), uint8(IKinfolioTrust.State.Closed));

        vm.warp(t0 + 10 * 365 days);
        bytes memory err = abi.encodeWithSelector(
            IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Closed
        );
        vm.prank(spouse);
        vm.expectRevert(err);
        trust.startClaim();
        vm.expectRevert(err);
        trust.collectAll();
        vm.prank(owner);
        vm.expectRevert(err);
        trust.checkIn();
    }

    function test_Rescue_ReturnsStrayTokensToOwner() public {
        vm.prank(owner);
        tsla.transfer(address(trust), 1e18); // mistake

        vm.prank(owner);
        trust.rescue(address(tsla));
        assertEq(tsla.balanceOf(owner), TSLA_BALANCE);
        assertEq(tsla.balanceOf(address(trust)), 0);
    }

    function test_Rescue_WorksAfterClose() public {
        vm.startPrank(owner);
        tsla.transfer(address(trust), 1e18);
        trust.close();
        trust.rescue(address(tsla));
        vm.stopPrank();
        assertEq(tsla.balanceOf(owner), TSLA_BALANCE);
    }

    function test_RevertWhen_RescuingAfterRelease() public {
        _release(trust);
        trust.collectAll();
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Released
            )
        );
        trust.rescue(address(tsla));
    }

    // ─── Config validation ──────────────────────────────────────────────────

    function test_RevertWhen_PeriodsOutOfBounds() public {
        vm.startPrank(owner);
        vm.expectRevert(IKinfolioTrust.InvalidPeriods.selector);
        trust.setPeriods(MIN_INACTIVITY - 1, CHALLENGE);
        vm.expectRevert(IKinfolioTrust.InvalidPeriods.selector);
        trust.setPeriods(INACTIVITY, MIN_CHALLENGE - 1);
        vm.expectRevert(IKinfolioTrust.InvalidPeriods.selector);
        trust.setPeriods(10 * 365 days + 1, CHALLENGE);
        vm.expectRevert(IKinfolioTrust.InvalidPeriods.selector);
        trust.setPeriods(INACTIVITY, 365 days + 1);
        trust.setPeriods(MIN_INACTIVITY, MIN_CHALLENGE); // inclusive minimums
        vm.stopPrank();
    }

    function test_RevertWhen_AssetListInvalid() public {
        address[] memory none = new address[](0);
        address[] memory tooMany = new address[](17);
        address[] memory zero = new address[](1);
        address[] memory eoa = new address[](1);
        eoa[0] = stranger;
        address[] memory self = new address[](1);
        self[0] = address(trust);
        address[] memory dup = new address[](2);
        dup[0] = address(tsla);
        dup[1] = address(tsla);

        vm.startPrank(owner);
        vm.expectRevert(IKinfolioTrust.InvalidAssetCount.selector);
        trust.setAssets(none);
        vm.expectRevert(IKinfolioTrust.InvalidAssetCount.selector);
        trust.setAssets(tooMany);
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.InvalidAsset.selector, address(0)));
        trust.setAssets(zero);
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.InvalidAsset.selector, stranger));
        trust.setAssets(eoa);
        vm.expectRevert(
            abi.encodeWithSelector(IKinfolioTrust.InvalidAsset.selector, address(trust))
        );
        trust.setAssets(self);
        vm.expectRevert(
            abi.encodeWithSelector(IKinfolioTrust.DuplicateAsset.selector, address(tsla))
        );
        trust.setAssets(dup);
        vm.stopPrank();
    }

    function test_SetAssets_ReplacesMembership() public {
        address[] memory onlyTsla = new address[](1);
        onlyTsla[0] = address(tsla);
        IKinfolioTrust.Grant[] memory g = new IKinfolioTrust.Grant[](1);
        g[0] = _grant(spouse, 10_000, 0, 0, IKinfolioTrust.Sleeve.Portfolio);

        vm.startPrank(owner);
        trust.setGrants(g); // drop the cash sleeve first
        trust.setAssets(onlyTsla);
        vm.stopPrank();

        assertTrue(trust.isAsset(address(tsla)));
        assertFalse(trust.isAsset(address(amzn)));
        assertFalse(trust.isAsset(address(usdg)));
        assertEq(trust.getAssets().length, 1);
    }

    function test_RevertWhen_RemovingCashAssetUnderCashSleeve() public {
        address[] memory noUsdg = new address[](2);
        noUsdg[0] = address(tsla);
        noUsdg[1] = address(amzn);
        vm.prank(owner);
        vm.expectRevert(IKinfolioTrust.CashSleeveNeedsCashAsset.selector);
        trust.setAssets(noUsdg);
    }

    function test_RevertWhen_GrantListInvalid() public {
        vm.startPrank(owner);

        vm.expectRevert(IKinfolioTrust.InvalidGrantCount.selector);
        trust.setGrants(new IKinfolioTrust.Grant[](0));
        vm.expectRevert(IKinfolioTrust.InvalidGrantCount.selector);
        trust.setGrants(new IKinfolioTrust.Grant[](13));

        IKinfolioTrust.Grant[] memory g = _familyGrants();
        g[0].beneficiary = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(IKinfolioTrust.InvalidBeneficiary.selector, address(0))
        );
        trust.setGrants(g);

        g = _familyGrants();
        g[0].beneficiary = owner;
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.InvalidBeneficiary.selector, owner));
        trust.setGrants(g);

        g = _familyGrants();
        g[0].beneficiary = address(trust);
        vm.expectRevert(
            abi.encodeWithSelector(IKinfolioTrust.InvalidBeneficiary.selector, address(trust))
        );
        trust.setGrants(g);

        g = _familyGrants();
        g[1].bps = 0;
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.ZeroShare.selector, 1));
        trust.setGrants(g);

        g = _familyGrants();
        g[2].unlockAt = uint40(block.timestamp + 100 * 365 days + 1);
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.InvalidSchedule.selector, 2));
        trust.setGrants(g);

        g = _familyGrants();
        g[3].vestDuration = 50 * 365 days + 1;
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.InvalidSchedule.selector, 3));
        trust.setGrants(g);

        vm.stopPrank();
    }

    function test_RevertWhen_SleeveSharesDoNotTotal100() public {
        IKinfolioTrust.Grant[] memory g = _familyGrants();
        g[0].bps = 3999;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.SharesMustTotal100.selector, IKinfolioTrust.Sleeve.Portfolio, 9999
            )
        );
        trust.setGrants(g);

        g = _familyGrants();
        g[3].bps = 5000;
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.SharesMustTotal100.selector, IKinfolioTrust.Sleeve.Cash, 5000
            )
        );
        trust.setGrants(g);
    }

    function test_RevertWhen_CashSleeveWithoutCashAsset() public {
        address[] memory noUsdg = new address[](1);
        noUsdg[0] = address(tsla);
        IKinfolioTrust.TrustConfig memory config = _config(noUsdg, _familyGrants());
        vm.prank(owner);
        vm.expectRevert(IKinfolioTrust.CashSleeveNeedsCashAsset.selector);
        factory.createTrust(config, bytes32(uint256(1)));
    }

    function test_WithoutCashGrants_UsdgFollowsPortfolio() public {
        IKinfolioTrust.Grant[] memory g = new IKinfolioTrust.Grant[](2);
        g[0] = _grant(spouse, 6000, 0, 0, IKinfolioTrust.Sleeve.Portfolio);
        g[1] = _grant(child, 4000, 0, 0, IKinfolioTrust.Sleeve.Portfolio);
        vm.prank(owner);
        trust.setGrants(g);

        assertFalse(trust.hasCashSleeve());
        assertEq(uint8(trust.sleeveOf(address(usdg))), uint8(IKinfolioTrust.Sleeve.Portfolio));
    }

    function test_SetGrants_IndexesNewBeneficiaries() public {
        IKinfolioTrust.Grant[] memory g = _familyGrants();
        g[0].beneficiary = stranger;
        vm.prank(owner);
        trust.setGrants(g);
        assertEq(factory.trustsFor(stranger)[0], address(trust));
    }
}
