// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

// Move to errors lib
error FeeGreaterThanScale();

contract GooFarm is ERC4626, Ownable2Step {
    using FixedPointMathLib for uint256;

    uint256 public protocolFee; // Out of 1e18
    uint256 public constant SCALE = 1e18;

    event FeeUpdated(uint256 oldFee, uint256 newFee);

    constructor(ERC20 goo) ERC4626(goo, "Farmed Goo", "xGOO") {}

    // TODO on deposit, include fee amount that mints protocol shares of GOO pool. 0 until fee switch.

    function setProtocolFee(uint256 newFee) public onlyOwner {
        if (newFee > SCALE) revert FeeGreaterThanScale();

        uint256 oldFee = protocolFee;
        protocolFee = newFee;

        emit FeeUpdated(oldFee, newFee);
    }

    function convertToShares(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view override returns (uint256) {
        return convertToShares(assets);
    }

    function previewMint(uint256 shares) public view override returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivUp(totalAssets(), supply);
    }

    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function previewRedeem(uint256 shares) public view override returns (uint256) {
        return convertToAssets(shares);
    }

    // Returns total GOO (less Gobbler and protocol fees) in the protocol
    function totalAssets() public view override returns (uint256) {
        // TODO
        return 1;
    }
}
