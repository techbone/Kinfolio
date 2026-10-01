// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {KinfolioTrust} from "../src/KinfolioTrust.sol";
import {IKinfolioTrust} from "../src/interfaces/IKinfolioTrust.sol";
import {MockFeeToken} from "./mocks/MockTokens.sol";
import {KinfolioBase} from "./utils/KinfolioBase.sol";

/// Collection, distribution, vesting, sleeves and fault isolation.
contract KinfolioTrustSettlementTest is KinfolioBase {
    uint256 internal constant SPOUSE = 0;
    uint256 internal constant CHILD_18 = 1;
    uint256 internal constant CHILD_25 = 2;
    uint256 internal constant PARENT = 3;

    KinfolioTrust internal trust;

    function setUp() public override {
        super.setUp();
        trust = _createFamilyTrust();
    }

    function _settle() internal {
        _release(trust);
        trust.collectAll();
    }

    // ─── Collect: never before release ──────────────────────────────────────

    function test_RevertWhen_CollectingBeforeRelease() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Active
            )
        );
        trust.collect(address(tsla));

        _startClaim(trust);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Challenge
            )
        );
        trust.collectAll();
        assertEq(tsla.balanceOf(owner), TSLA_BALANCE);
    }

    function test_RevertWhen_DistributingBeforeRelease() public {
        _startClaim(trust);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Challenge
            )
        );
        trust.distribute(SPOUSE, address(tsla));
    }

    // ─── Collect ────────────────────────────────────────────────────────────

    function test_CollectAll_PullsEveryCoveredAsset() public {
        _release(trust);

        vm.expectEmit(true, false, false, true, address(trust));
        emit IKinfolioTrust.Collected(address(tsla), TSLA_BALANCE);
        vm.prank(stranger); // permissionless
        trust.collectAll();

        assertEq(tsla.balanceOf(owner), 0);
        assertEq(amzn.balanceOf(owner), 0);
        assertEq(usdg.balanceOf(owner), 0);
        assertEq(trust.collected(address(tsla)), TSLA_BALANCE);
        assertEq(trust.collected(address(amzn)), AMZN_BALANCE);
        assertEq(trust.collected(address(usdg)), USDG_BALANCE);
    }

    function test_Collect_CapsAtAllowance() public {
        vm.prank(owner);
        tsla.approve(address(trust), 10e18);
        assertEq(trust.coverage(address(tsla)), 10e18);

        _release(trust);
        assertEq(trust.collect(address(tsla)), 10e18);
        assertEq(tsla.balanceOf(owner), TSLA_BALANCE - 10e18);
    }

    function test_Collect_ReturnsZeroWithoutAllowance() public {
        vm.prank(owner);
        tsla.approve(address(trust), 0);
        _release(trust);
        assertEq(trust.collect(address(tsla)), 0);
        assertEq(trust.collected(address(tsla)), 0);
    }

    function test_RevertWhen_CollectingUnknownAsset() public {
        _release(trust);
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.UnknownAsset.selector, stranger));
        trust.collect(stranger);
    }

    function test_Collect_RepeatableForLateArrivals() public {
        _settle();
        tsla.mint(owner, 10e18); // e.g. a pending order fills after release

        assertEq(trust.collect(address(tsla)), 10e18);
        assertEq(trust.collected(address(tsla)), TSLA_BALANCE + 10e18);
        assertEq(trust.claimable(SPOUSE, address(tsla)), (TSLA_BALANCE + 10e18) * 4000 / 10_000);
    }

    function test_Collect_FollowsOwnerTradingWhileAlive() public {
        vm.startPrank(owner);
        tsla.transfer(stranger, 60e18); // sells 60 TSLA after setting up the trust
        vm.stopPrank();
        amzn.mint(owner, 25e18); // buys more AMZN

        _settle();
        assertEq(trust.collected(address(tsla)), 40e18);
        assertEq(trust.collected(address(amzn)), 75e18);
    }

    function test_Collect_AfterIssuerBurnTakesWhatRemains() public {
        tsla.adminBurn(owner, 30e18);
        _settle();
        assertEq(trust.collected(address(tsla)), 70e18);
    }

    function test_Collect_CountsBalanceDeltaNotRequestedAmount() public {
        MockFeeToken fee = new MockFeeToken();
        fee.mint(owner, 100e18);
        address[] memory assets = new address[](1);
        assets[0] = address(fee);
        IKinfolioTrust.Grant[] memory g = new IKinfolioTrust.Grant[](1);
        g[0] = _grant(spouse, 10_000, 0, 0, IKinfolioTrust.Sleeve.Portfolio);

        vm.prank(owner);
        KinfolioTrust feeTrust =
            KinfolioTrust(factory.createTrust(_config(assets, g), bytes32("fee")));
        vm.prank(owner);
        fee.approve(address(feeTrust), type(uint256).max);

        _release(feeTrust);
        assertEq(feeTrust.collect(address(fee)), 99e18);
        assertEq(feeTrust.collected(address(fee)), 99e18);
        assertEq(fee.balanceOf(address(feeTrust)), 99e18);
    }

    // ─── Fault isolation: issuer pause ──────────────────────────────────────

    function test_CollectAll_IsolatesPausedAsset() public {
        _release(trust);
        tsla.setPaused(true);

        vm.expectEmit(true, false, false, false, address(trust));
        emit IKinfolioTrust.CollectFailed(address(tsla));
        trust.collectAll();

        assertEq(trust.collected(address(tsla)), 0);
        assertEq(trust.collected(address(amzn)), AMZN_BALANCE);
        assertEq(trust.collected(address(usdg)), USDG_BALANCE);

        tsla.setPaused(false);
        assertEq(trust.collect(address(tsla)), TSLA_BALANCE);
    }

    function test_DistributeAll_IsolatesPausedAsset() public {
        _settle();
        amzn.setPaused(true);

        vm.expectEmit(true, true, false, false, address(trust));
        emit IKinfolioTrust.DistributeFailed(SPOUSE, address(amzn));
        trust.distributeAll(SPOUSE);

        assertEq(tsla.balanceOf(spouse), 40e18);
        assertEq(amzn.balanceOf(spouse), 0);
        assertEq(trust.distributed(SPOUSE, address(amzn)), 0);

        amzn.setPaused(false);
        trust.distributeAll(SPOUSE);
        assertEq(amzn.balanceOf(spouse), 20e18);
    }

    // ─── Distribute ─────────────────────────────────────────────────────────

    function test_Distribute_PaysStoredBeneficiaryWhoeverCalls() public {
        _settle();

        vm.expectEmit(true, true, true, true, address(trust));
        emit IKinfolioTrust.Distributed(SPOUSE, spouse, address(tsla), 40e18);
        vm.prank(stranger);
        trust.distribute(SPOUSE, address(tsla));

        assertEq(tsla.balanceOf(spouse), 40e18);
        assertEq(tsla.balanceOf(stranger), 0);
    }

    function test_Distribute_IsIdempotent() public {
        _settle();
        trust.distribute(SPOUSE, address(tsla));
        assertEq(trust.distribute(SPOUSE, address(tsla)), 0);
        assertEq(tsla.balanceOf(spouse), 40e18);
    }

    function test_Distribute_RespectsSleeves() public {
        _settle();
        trust.distributeAll(SPOUSE);
        assertEq(tsla.balanceOf(spouse), 40e18);
        assertEq(amzn.balanceOf(spouse), 20e18);
        assertEq(usdg.balanceOf(spouse), 0); // USDG belongs to the cash sleeve

        assertEq(trust.entitlement(PARENT, address(tsla)), 0);
        assertEq(trust.entitlement(PARENT, address(usdg)), USDG_BALANCE);
    }

    function test_RevertWhen_DistributingUnknownGrant() public {
        _settle();
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.GrantNotFound.selector, 4));
        trust.distribute(4, address(tsla));
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.GrantNotFound.selector, 4));
        trust.distributeAll(4);
    }

    // ─── Vesting ────────────────────────────────────────────────────────────

    function test_ChildTranchesUnlockAtEachAge() public {
        _settle();
        assertEq(trust.claimable(CHILD_18, address(tsla)), 0);

        vm.warp(t0 + CHILD_AT_18 - 1);
        assertEq(trust.claimable(CHILD_18, address(tsla)), 0);

        vm.warp(t0 + CHILD_AT_18);
        trust.distributeAll(CHILD_18);
        assertEq(tsla.balanceOf(child), 30e18);
        assertEq(amzn.balanceOf(child), 15e18);
        assertEq(trust.claimable(CHILD_25, address(tsla)), 0);

        vm.warp(t0 + CHILD_AT_25);
        trust.distributeAll(CHILD_25);
        assertEq(tsla.balanceOf(child), 60e18);
        assertEq(amzn.balanceOf(child), 30e18);
    }

    function test_AllowanceVestsLinearly() public {
        _settle();
        uint256 start = trust.releasedAt();

        vm.warp(start + ALLOWANCE_PERIOD / 4);
        trust.distribute(PARENT, address(usdg));
        assertEq(usdg.balanceOf(parent), USDG_BALANCE / 4);

        vm.warp(start + ALLOWANCE_PERIOD / 2);
        trust.distribute(PARENT, address(usdg));
        assertEq(usdg.balanceOf(parent), USDG_BALANCE / 2);

        vm.warp(start + ALLOWANCE_PERIOD + 365 days);
        trust.distribute(PARENT, address(usdg));
        assertEq(usdg.balanceOf(parent), USDG_BALANCE);
        assertEq(trust.claimable(PARENT, address(usdg)), 0);
    }

    function test_UnlockInThePastStartsAtRelease() public {
        IKinfolioTrust.Grant[] memory g = _familyGrants();
        g[1].unlockAt = uint40(t0 + 1 days); // already reached by release time
        vm.prank(owner);
        trust.setGrants(g);

        _settle();
        assertEq(trust.claimable(CHILD_18, address(tsla)), 30e18);
    }

    function test_VestingStartsAtUnlockWhenLater() public {
        IKinfolioTrust.Grant[] memory g = _familyGrants();
        g[1].vestDuration = 365 days; // vest over a year after turning 18
        vm.prank(owner);
        trust.setGrants(g);
        _settle();

        vm.warp(t0 + CHILD_AT_18);
        assertEq(trust.claimable(CHILD_18, address(tsla)), 0);
        vm.warp(t0 + CHILD_AT_18 + 365 days / 2);
        assertEq(trust.claimable(CHILD_18, address(tsla)), 15e18);
    }

    function test_WithoutCashSleeve_UsdgSplitsLikeThePortfolio() public {
        IKinfolioTrust.Grant[] memory g = new IKinfolioTrust.Grant[](2);
        g[0] = _grant(spouse, 7500, 0, 0, IKinfolioTrust.Sleeve.Portfolio);
        g[1] = _grant(child, 2500, 0, 0, IKinfolioTrust.Sleeve.Portfolio);
        vm.prank(owner);
        trust.setGrants(g);

        _settle();
        trust.distributeAll(0);
        trust.distributeAll(1);
        assertEq(usdg.balanceOf(spouse), USDG_BALANCE * 3 / 4);
        assertEq(usdg.balanceOf(child), USDG_BALANCE / 4);
    }

    // ─── ERC-8056: corporate actions flow through raw-unit accounting ───────

    function test_SplitDuringLockupReachesHeirInFull() public {
        _settle();
        uint256 rawBefore = trust.entitlement(CHILD_18, address(tsla));

        tsla.updateMultiplier(2e18); // 2:1 split while the tranche is locked

        assertEq(trust.entitlement(CHILD_18, address(tsla)), rawBefore);
        vm.warp(t0 + CHILD_AT_18);
        trust.distribute(CHILD_18, address(tsla));
        assertEq(tsla.balanceOf(child), 30e18);
        assertEq(tsla.balanceOfUI(child), 60e18); // twice the shares
    }

    // ─── Full settlement accounting ─────────────────────────────────────────

    function test_FullSettlementAccountsForEveryToken() public {
        // awkward amounts to force rounding
        tsla.mint(owner, 7);
        usdg.mint(owner, 3);
        _settle();
        vm.warp(t0 + 100 * 365 days);
        for (uint256 i; i < 4; ++i) {
            trust.distributeAll(i);
        }

        address[] memory assets = _assets();
        for (uint256 a; a < assets.length; ++a) {
            uint256 paid;
            for (uint256 i; i < 4; ++i) {
                paid += trust.distributed(i, assets[a]);
            }
            uint256 dust = trust.collected(assets[a]) - paid;
            assertLe(dust, 4, "dust bounded by grant count");
            assertEq(IERC20(assets[a]).balanceOf(address(trust)), dust);
        }
    }

    // ─── Heir wallet rotation ───────────────────────────────────────────────

    function test_TransferGrant_RedirectsFuturePayouts() public {
        _settle();
        address newWallet = makeAddr("childNewWallet");

        vm.expectEmit(true, true, true, false, address(trust));
        emit IKinfolioTrust.GrantTransferred(CHILD_18, child, newWallet);
        vm.prank(child);
        trust.transferGrant(CHILD_18, newWallet);

        vm.warp(t0 + CHILD_AT_18);
        trust.distribute(CHILD_18, address(tsla));
        assertEq(tsla.balanceOf(newWallet), 30e18);
        assertEq(tsla.balanceOf(child), 0);
        assertEq(factory.trustsFor(newWallet)[0], address(trust));
        // the other tranche is untouched
        assertEq(trust.getGrants()[CHILD_25].beneficiary, child);
    }

    function test_RevertWhen_TransferGrantMisused() public {
        address newWallet = makeAddr("new");
        vm.prank(child);
        vm.expectRevert(
            abi.encodeWithSelector(
                IKinfolioTrust.InvalidState.selector, IKinfolioTrust.State.Active
            )
        );
        trust.transferGrant(CHILD_18, newWallet);

        _settle();
        vm.prank(stranger);
        vm.expectRevert(IKinfolioTrust.NotBeneficiary.selector);
        trust.transferGrant(CHILD_18, stranger);

        vm.startPrank(child);
        vm.expectRevert(
            abi.encodeWithSelector(IKinfolioTrust.InvalidBeneficiary.selector, address(0))
        );
        trust.transferGrant(CHILD_18, address(0));
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.InvalidBeneficiary.selector, owner));
        trust.transferGrant(CHILD_18, owner);
        vm.expectRevert(abi.encodeWithSelector(IKinfolioTrust.GrantNotFound.selector, 9));
        trust.transferGrant(9, newWallet);
        vm.stopPrank();
    }
}
