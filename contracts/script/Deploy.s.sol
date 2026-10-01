// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";

import {KinfolioFactory} from "../src/KinfolioFactory.sol";

/// Deploys the factory (which deploys the trust implementation) with the
/// profile for the current chain:
///   46630 Robinhood Chain testnet  demo        60s inactivity / 60s challenge
///   4663  Robinhood Chain mainnet  production  30d inactivity / 7d challenge
contract Deploy is Script {
    address internal constant USDG_TESTNET = 0x7E955252E15c84f5768B83c41a71F9eba181802F;
    address internal constant USDG_MAINNET = 0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168;

    function run() external returns (KinfolioFactory factory) {
        (address usdg, uint32 minInactivity, uint32 minChallenge) = profile(block.chainid);

        vm.startBroadcast();
        factory = new KinfolioFactory(usdg, minInactivity, minChallenge);
        vm.stopBroadcast();

        console.log("chain          ", block.chainid);
        console.log("factory        ", address(factory));
        console.log("implementation ", factory.IMPLEMENTATION());
        console.log("cash asset     ", usdg);
        console.log("min inactivity ", minInactivity);
        console.log("min challenge  ", minChallenge);
    }

    function profile(uint256 chainId)
        public
        pure
        returns (address usdg, uint32 minInactivity, uint32 minChallenge)
    {
        if (chainId == 46630) return (USDG_TESTNET, 60, 60);
        if (chainId == 4663) return (USDG_MAINNET, 30 days, 7 days);
        revert("Deploy: unsupported chain");
    }
}
