// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// Plain ERC-20 with configurable decimals (USDG uses 6).
contract MockERC20 is ERC20 {
    uint8 private immutable _decimals;

    constructor(string memory symbol_, uint8 decimals_) ERC20(symbol_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// Mirrors the Robinhood Chain stock token surface the trust interacts with:
/// ERC-8056 UI multiplier, issuer pause, issuer burn.
contract MockStockToken is MockERC20 {
    uint256 public uiMultiplier = 1e18;
    bool public paused;

    error TokenPaused();

    constructor(string memory symbol_) MockERC20(symbol_, 18) {}

    function balanceOfUI(address account) external view returns (uint256) {
        return balanceOf(account) * uiMultiplier / 1e18;
    }

    /// e.g. 2:1 split or reinvested dividend. Raw balances never change.
    function updateMultiplier(uint256 multiplier) external {
        uiMultiplier = multiplier;
    }

    function setPaused(bool paused_) external {
        paused = paused_;
    }

    function adminBurn(address from, uint256 amount) external {
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (paused) revert TokenPaused();
        super._update(from, to, value);
    }
}

/// Burns 1% of every transfer, to prove `collected` uses the balance delta.
contract MockFeeToken is MockERC20 {
    constructor() MockERC20("FEE", 18) {}

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) return super._update(from, to, value);
        uint256 fee = value / 100;
        super._update(from, address(0), fee);
        super._update(from, to, value - fee);
    }
}
