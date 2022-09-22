// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IFarmController} from "./interfaces/IFarmController.sol";

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

    IFarmController public farmController;

    uint256 public protocolBalance; // TODO remove this - fees accrued via xGOO balance in treasury
    uint256 public gobblersBalance;
    // Remaining GOO belongs to xGOO holders

    // TODO def need this to manage protocol+Goo and then gobbler partitions accruing over time
    uint256 public lastRebalanceTimestamp;
    uint256 public lastRebalanceTotalGoo;

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    constructor(ERC20 goo) ERC4626(goo, "GOO Farm Shares", "xGOO") {}

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
        (uint256 fee, uint256 netShares) = farmController.calculateProtocolFee(shares);

        // Calculate new assets recieved after share fee cut
        assets = previewRedeem(netShares);

        _burn(owner, netShares);

        transferFrom(owner, farmController.treasury(), fee);

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
        (uint256 fee, uint256 netShares) = farmController.calculateProtocolFee(shares);

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(netShares)) != 0, "ZERO_ASSETS");

        _burn(owner, netShares);

        transferFrom(owner, farmController.treasury(), fee);

        // TODO update to include fee
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);
    }

    // Returns total GOO (less Gobbler and protocol fees) in the protocol
    function totalAssets() public view override returns (uint256) {
        // TODO
        return 1;
    }
}
