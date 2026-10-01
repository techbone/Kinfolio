// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Vesting
/// @notice Pure schedule math, kept separate so it can be fuzzed in isolation.
library Vesting {
    /// @return The part of `total` vested at time `t` for a schedule starting at
    /// `start`. Lump sum when `duration == 0`, otherwise linear. Monotonic in
    /// both `t` and `total`, and never exceeds `total`.
    function vested(uint256 total, uint256 start, uint256 duration, uint256 t)
        internal
        pure
        returns (uint256)
    {
        if (t < start) return 0;
        if (duration == 0 || t >= start + duration) return total;
        return Math.mulDiv(total, t - start, duration);
    }
}
