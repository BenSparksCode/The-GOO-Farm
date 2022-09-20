// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

// Move to errors lib
error FeeGreaterThanScale();
error ZeroAddressTreasury();

contract GooFarm is ERC4626, Ownable2Step {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    address public protocolTreasury;
    uint256 public protocolFee; // Out of 1e18
    uint256 public constant SCALE = 1e18;

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    constructor(ERC20 goo) ERC4626(goo, "Farmed Goo", "xGOO") {}

    // TODO on deposit, include fee amount that mints protocol shares of GOO pool. 0 until fee switch.

    function setProtocolFee(uint256 newFee) public onlyOwner {
        if (newFee > SCALE) revert FeeGreaterThanScale();

        uint256 oldFee = protocolFee;
        protocolFee = newFee;

        emit FeeUpdated(oldFee, newFee);
    }

    function setProtocolTreasury(address newTreasury) public onlyOwner {
        if (newTreasury == address(0)) revert ZeroAddressTreasury();

        address oldTreasury = protocolTreasury;
        protocolTreasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    // If fee-switch enabled, only take fees on withdraw/redeem, after service has been provided

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // TODO skip if fee == 0
        (uint256 fee, uint256 netShares) = _takeFee(shares);

        // Calculate new assets recieved after share fee cut
        assets = previewRedeem(netShares);

        _burn(owner, netShares);

        transferFrom(owner, protocolTreasury, fee);

        // TODO update to include fee
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        // TODO skip if fee == 0
        (uint256 fee, uint256 netShares) = _takeFee(shares);

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(netShares)) != 0, "ZERO_ASSETS");

        _burn(owner, netShares);

        transferFrom(owner, protocolTreasury, fee);

        // TODO update to include fee
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    // Returns total GOO (less Gobbler and protocol fees) in the protocol
    function totalAssets() public view override returns (uint256) {
        // TODO
        return 1;
    }

    // TODO Convert to mulDivUp
    function _takeFee(uint256 _amount) internal returns (uint256 fee, uint256 netAmount) {
        fee = (protocolFee * _amount) / SCALE;
        netAmount = _amount - fee;
    }
}
