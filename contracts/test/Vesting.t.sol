// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {Vesting} from "../src/libraries/Vesting.sol";

contract VestingTest is Test {
    uint256 internal constant MAX_TOTAL = 1e36;
    uint256 internal constant MAX_TIME = type(uint40).max;
    uint256 internal constant MAX_DURATION = 50 * 365 days;

    function testFuzz_NeverExceedsTotal(uint256 total, uint256 start, uint256 duration, uint256 t)
        public
        pure
    {
        total = bound(total, 0, MAX_TOTAL);
        start = bound(start, 0, MAX_TIME);
        duration = bound(duration, 0, MAX_DURATION);
        t = bound(t, 0, MAX_TIME + MAX_DURATION);
        assertLe(Vesting.vested(total, start, duration, t), total);
    }

    function testFuzz_MonotonicInTime(
        uint256 total,
        uint256 start,
        uint256 duration,
        uint256 t1,
        uint256 t2
    ) public pure {
        total = bound(total, 0, MAX_TOTAL);
        start = bound(start, 0, MAX_TIME);
        duration = bound(duration, 0, MAX_DURATION);
        t1 = bound(t1, 0, MAX_TIME + MAX_DURATION);
        t2 = bound(t2, t1, MAX_TIME + MAX_DURATION);
        assertLe(
            Vesting.vested(total, start, duration, t1), Vesting.vested(total, start, duration, t2)
        );
    }

    function testFuzz_MonotonicInTotal(
        uint256 total1,
        uint256 total2,
        uint256 start,
        uint256 duration,
        uint256 t
    ) public pure {
        total1 = bound(total1, 0, MAX_TOTAL);
        total2 = bound(total2, total1, MAX_TOTAL);
        start = bound(start, 0, MAX_TIME);
        duration = bound(duration, 0, MAX_DURATION);
        t = bound(t, 0, MAX_TIME + MAX_DURATION);
        assertLe(
            Vesting.vested(total1, start, duration, t), Vesting.vested(total2, start, duration, t)
        );
    }

    function testFuzz_NothingBeforeStart(uint256 total, uint256 start, uint256 duration, uint256 t)
        public
        pure
    {
        start = bound(start, 1, MAX_TIME);
        t = bound(t, 0, start - 1);
        assertEq(Vesting.vested(total, start, duration, t), 0);
    }

    function testFuzz_EverythingAfterEnd(uint256 total, uint256 start, uint256 duration, uint256 t)
        public
        pure
    {
        total = bound(total, 0, MAX_TOTAL);
        start = bound(start, 0, MAX_TIME);
        duration = bound(duration, 0, MAX_DURATION);
        t = bound(t, start + duration, MAX_TIME + MAX_DURATION);
        assertEq(Vesting.vested(total, start, duration, t), total);
    }

    function test_LumpSumAtStart() public pure {
        assertEq(Vesting.vested(100, 50, 0, 49), 0);
        assertEq(Vesting.vested(100, 50, 0, 50), 100);
    }

    function test_LinearMidpoint() public pure {
        assertEq(Vesting.vested(100, 0, 10, 5), 50);
        assertEq(Vesting.vested(100, 0, 3, 1), 33); // floors
    }
}
