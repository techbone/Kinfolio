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

/// Full lifecycle against the factory as actually deployed, with the chain's real
/// stock tokens and USDG. Run offline with: forge test --no-match-path "test/fork/*"
abstract contract RobinhoodForkTest is Test {
    KinfolioFactory internal constant FACTORY =
        KinfolioFactory(0xbdEF1e8cb7DB12a81d6C32f5E57D2ccE41b4A90F);
    address internal constant IMPLEMENTATION = 0x821D8133adfd1fc9aE2e90195C5Ac0E4bdbEdaD7;

    address internal owner = makeAddr("owner");
    address internal spouse = makeAddr("spouse");
    address internal parent = makeAddr("parent");

    function _rpc() internal pure virtual returns (string memory);
    function _chainId() internal pure virtual returns (uint256);
    function _stocks() internal pure virtual returns (address, address);
    function _usdg() internal pure virtual returns (address);
    function _minimums() internal pure virtual returns (uint32 inactivity, uint32 challenge);

    function setUp() public {
        vm.createSelectFork(_rpc());
        assertEq(block.chainid, _chainId());
    }

    function test_Fork_DeployedProfile() public view {
        (uint32 minInactivity, uint32 minChallenge) = _minimums();
        KinfolioTrust impl = KinfolioTrust(IMPLEMENTATION);
        assertEq(FACTORY.IMPLEMENTATION(), IMPLEMENTATION);
        assertEq(impl.FACTORY(), address(FACTORY));
        assertEq(impl.CASH_ASSET(), _usdg());
        assertEq(impl.MIN_INACTIVITY(), minInactivity);
        assertEq(impl.MIN_CHALLENGE(), minChallenge);
        assertEq(impl.owner(), address(0)); // implementation is locked
    }

    function test_Fork_FullLifecycleWithRealStockTokens() public {
        (address stockA, address stockB) = _stocks();
        address usdg = _usdg();
        (uint32 inactivity, uint32 challenge) = _minimums();
        deal(stockA, owner, 5e18);
        deal(stockB, owner, 3e18);
        deal(usdg, owner, 1_000e6);

        address[] memory assets = new address[](3);
        assets[0] = stockA;
        assets[1] = stockB;
        assets[2] = usdg;
        IKinfolioTrust.Grant[] memory grants = new IKinfolioTrust.Grant[](2);
        grants[0] = IKinfolioTrust.Grant(spouse, 10_000, 0, 0, IKinfolioTrust.Sleeve.Portfolio);
        grants[1] = IKinfolioTrust.Grant(parent, 10_000, 0, 600, IKinfolioTrust.Sleeve.Cash);

        vm.startPrank(owner);
        KinfolioTrust trust = KinfolioTrust(
            FACTORY.createTrust(
                IKinfolioTrust.TrustConfig(inactivity, challenge, assets, grants), bytes32("fork")
            )
        );
        for (uint256 i; i < assets.length; ++i) {
            IERC20(assets[i]).approve(address(trust), type(uint256).max);
        }
        vm.stopPrank();

        // owner keeps custody while alive
        assertEq(IERC20(stockA).balanceOf(owner), 5e18);
        assertEq(trust.coverage(stockA), 5e18);

        vm.warp(vm.getBlockTimestamp() + inactivity + 1);
        vm.prank(spouse);
        trust.startClaim();
        vm.warp(vm.getBlockTimestamp() + challenge + 1);
        trust.finalize();
        trust.collectAll();

        assertEq(trust.collected(stockA), 5e18);
        assertEq(trust.collected(stockB), 3e18);
        assertEq(trust.collected(usdg), 1_000e6);

        trust.distributeAll(0);
        assertEq(IERC20(stockA).balanceOf(spouse), 5e18);
        assertEq(IERC20(stockB).balanceOf(spouse), 3e18);
        assertEq(
            IERC8056(stockA).balanceOfUI(spouse), 5e18 * IERC8056(stockA).uiMultiplier() / 1e18
        );

        vm.warp(vm.getBlockTimestamp() + 300);
        trust.distribute(1, usdg);
        assertEq(IERC20(usdg).balanceOf(parent), 500e6); // half the allowance
    }
}

contract RobinhoodTestnetForkTest is RobinhoodForkTest {
    function _rpc() internal pure override returns (string memory) {
        return "robinhood_testnet";
    }

    function _chainId() internal pure override returns (uint256) {
        return 46630;
    }

    function _stocks() internal pure override returns (address, address) {
        return
            (0xC9f9c86933092BbbfFF3CCb4b105A4A94bf3Bd4E, 0x5884aD2f920c162CFBbACc88C9C51AA75eC09E02);
    }

    function _usdg() internal pure override returns (address) {
        return 0x7E955252E15c84f5768B83c41a71F9eba181802F;
    }

    function _minimums() internal pure override returns (uint32, uint32) {
        return (60, 60);
    }
}

contract RobinhoodMainnetForkTest is RobinhoodForkTest {
    function _rpc() internal pure override returns (string memory) {
        return "robinhood";
    }

    function _chainId() internal pure override returns (uint256) {
        return 4663;
    }

    function _stocks() internal pure override returns (address, address) {
        return
            (0x322F0929c4625eD5bAd873c95208D54E1c003b2d, 0x12f190a9F9d7D37a250758b26824B97CE941bF54);
    }

    function _usdg() internal pure override returns (address) {
        return 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;
    }

    function _minimums() internal pure override returns (uint32, uint32) {
        return (30 days, 7 days);
    }
}
