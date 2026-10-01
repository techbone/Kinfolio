// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {KinfolioFactory} from "../../src/KinfolioFactory.sol";
import {KinfolioTrust} from "../../src/KinfolioTrust.sol";
import {IKinfolioTrust} from "../../src/interfaces/IKinfolioTrust.sol";

interface IERC8056 {
    function uiMultiplier() external view returns (uint256);
    function balanceOfUI(address account) external view returns (uint256);
}

/// Full lifecycle against the live Robinhood Chain testnet stock tokens and USDG.
/// Run offline with: forge test --no-match-path "test/fork/*"
contract RobinhoodTestnetForkTest is Test {
    address internal constant TSLA = 0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E;
    address internal constant AMZN = 0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02;
    address internal constant USDG = 0x7E955252E15c84f5768B83c41a71F9eba181802F;

    KinfolioFactory internal factory;
    address internal owner = makeAddr("owner");
    address internal spouse = makeAddr("spouse");
    address internal parent = makeAddr("parent");

    function setUp() public {
        vm.createSelectFork("robinhood_testnet");
        assertEq(block.chainid, 46630);
        factory = new KinfolioFactory(USDG, 60, 60); // demo profile

        deal(TSLA, owner, 5e18);
        deal(AMZN, owner, 3e18);
        deal(USDG, owner, 1_000e6);
    }

    function test_Fork_FullLifecycleWithRealStockTokens() public {
        address[] memory assets = new address[](3);
        assets[0] = TSLA;
        assets[1] = AMZN;
        assets[2] = USDG;
        IKinfolioTrust.Grant[] memory grants = new IKinfolioTrust.Grant[](2);
        grants[0] = IKinfolioTrust.Grant(spouse, 10_000, 0, 0, IKinfolioTrust.Sleeve.Portfolio);
        grants[1] = IKinfolioTrust.Grant(parent, 10_000, 0, 600, IKinfolioTrust.Sleeve.Cash);

        vm.startPrank(owner);
        KinfolioTrust trust = KinfolioTrust(
            factory.createTrust(IKinfolioTrust.TrustConfig(120, 60, assets, grants), bytes32(0))
        );
        for (uint256 i; i < assets.length; ++i) {
            IERC20(assets[i]).approve(address(trust), type(uint256).max);
        }
        vm.stopPrank();

        // owner keeps custody while alive
        assertEq(IERC20(TSLA).balanceOf(owner), 5e18);
        assertEq(trust.coverage(TSLA), 5e18);

        vm.warp(vm.getBlockTimestamp() + 121);
        vm.prank(spouse);
        trust.startClaim();
        vm.warp(vm.getBlockTimestamp() + 61);
        trust.finalize();
        trust.collectAll();

        assertEq(trust.collected(TSLA), 5e18);
        assertEq(trust.collected(AMZN), 3e18);
        assertEq(trust.collected(USDG), 1_000e6);

        trust.distributeAll(0);
        assertEq(IERC20(TSLA).balanceOf(spouse), 5e18);
        assertEq(IERC20(AMZN).balanceOf(spouse), 3e18);
        assertEq(IERC8056(TSLA).balanceOfUI(spouse), 5e18 * IERC8056(TSLA).uiMultiplier() / 1e18);

        vm.warp(vm.getBlockTimestamp() + 300);
        trust.distribute(1, USDG);
        assertEq(IERC20(USDG).balanceOf(parent), 500e6); // half the allowance
    }
}
