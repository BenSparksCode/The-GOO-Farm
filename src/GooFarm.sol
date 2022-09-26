// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IFarmController} from "./interfaces/IFarmController.sol";
import {IArtGobblers} from "./interfaces/IArtGobblers.sol";
import {IGobblerPen} from "./interfaces/IGobblerPen.sol";

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

// Move to errors lib
error FeeGreaterThanScale();
error ZeroAddressTreasury();
error NotGobblerOwner();

// TODO add pause function for deposits, keep ownable

contract GooFarm is ERC4626, Ownable2Step, ERC721TokenReceiver {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    IFarmController public farmController;
    IArtGobblers public artGobblers;
    IGobblerPen public gobblerPen;

    uint256 public protocolBalance; // TODO remove this - fees accrued via xGOO balance in treasury
    uint256 public gobblersBalance;
    // Remaining GOO belongs to xGOO holders

    // TODO struct packing - reads and writes for all slots on updateBalances()
    struct FarmData {
        uint256 lastTimestamp;
        uint256 lastTotalGooBalance;
        uint256 totalGobblersBalance;
    }

    struct GobblerDepositData {
        uint256 lastTimestamp;
        uint256 totalGobblersBalanceAtDeposit;
    }

    FarmData public farmData;
    mapping(uint256 => GobblerDepositData) public gobblerData; // nftID -> data

    event FeeUpdated(uint256 oldFee, uint256 newFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    constructor(
        ERC20 goo,
        IFarmController _farmController,
        IArtGobblers _artGobblers,
        IGobblerPen _gobblerPen
    ) ERC4626(goo, "Goo Farm", "xGOO") {
        farmController = _farmController;
        artGobblers = _artGobblers;
        gobblerPen = _gobblerPen;

        farmData = FarmData(0, block.timestamp, 0);
    }

    // TODO add deposit/mint overrides with emissions goo

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

    /*//////////////////////////////////////////////////////////////
                            INTERNAL ACCOUNTING
    //////////////////////////////////////////////////////////////*/

    /// @notice Internal logic for depositing a gobbler NFT and
    /// recieving an xGobbler NFT share
    /// @param from Account to deposit gobbler from.
    /// @param to Account to send receipt token to.
    /// @param gobblerID ID of gobbler to deposit.
    function _depositGobbler(
        address from,
        address to,
        uint256 gobblerID
    ) internal {
        // pull Gobbler NFT from ArtGobblers
        artGobblers.transferFrom(from, address(this), gobblerID);

        if (to == address(0)) to = from;
        // Send receipt token to specified to address
        gobblerPen.mintForGooFarm(to, gobblerID);

        // Update farm and gobbler data
        _updateBalances();
        gobblerData[gobblerID].lastTimestamp = block.timestamp;
        gobblerData[gobblerID].totalGobblersBalanceAtDeposit = farmData.totalGobblersBalance;
    }

    /// @notice Internal logic for withdrawing a gobbler NFT,
    /// burning the associated xGobbler NFT share,
    /// and receiving any accrued goo rewards.
    /// @param to Account to send gobbler and goo to.
    /// @param gobblerID ID of gobbler to withdraw.
    function _withdrawGobbler(address to, uint256 gobblerID) internal {
        if (gobblerPen.ownerOf(gobblerID) != msg.sender) revert NotGobblerOwner();

        uint256 gobblerMultiple = artGobblers.getGobblerEmissionMultiple(gobblerID);

        _updateBalances();

        uint256 gobblerGooSinceDeposit = farmData.totalGobblersBalance - gobblerData[gobblerID].totalGobblersBalanceAtDeposit;
        uint256 gooRewards = (gobblerMultiple * gobblerGooSinceDeposit) / artGobblers.getUserEmissionMultiple(address(this));

        // Burn receipt NFT
        gobblerPen.burnForGooFarm(gobblerID);

        // Send gobbler
        artGobblers.transferFrom(address(this), to, gobblerID);

        // Send goo
        artGobblers.transferGoo(to, gooRewards);

        // TODO dont need to delete this - will be overwritten on next deposit
        // check before removing this line tho
        delete gobblerData[gobblerID];

        farmData.lastTotalGooBalance -= gooRewards;
        farmData.totalGobblersBalance -= gooRewards;
    }

    /// @notice Internal logic for depositing goo and recieving xGOO shares
    /// @param from Account to pull goo from.
    /// @param gooAmount Amount of goo to deposit.
    /// @param usingERC20 Optional flag, if true will use ERC20 goo.
    function _depositGoo(
        address from,
        uint256 gooAmount,
        bool usingERC20
    ) internal {
        if (usingERC20) {
            // asset (in ERC4626 vault) is goo, set in constructor
            asset.transferFrom(from, address(this), gooAmount);
            artGobblers.addGoo(gooAmount);
        } else {
            // TODO update when ArtGobblers PR is finalized
            artGobblers.transferGooFrom(from, address(this), gooAmount);
        }
    }

    // This balance update should be called before any goo deposits of withdraws
    function _updateBalances() internal {
        uint256 currentTotalGoo = artGobblers.gooBalance(address(this));
        uint256 totalBalanceDiff = currentTotalGoo - farmData.lastTotalGooBalance;

        uint256 gobblerCut = farmController.calculateGobblerCut(totalBalanceDiff);

        farmData.lastTotalGooBalance += currentTotalGoo;
        farmData.totalGobblersBalance += gobblerCut;
        farmData.lastTimestamp = block.timestamp;
    }

    // Returns total goo attributed to xGOO holders
    function totalAssets() public view override returns (uint256) {
        return farmData.lastTotalGooBalance - farmData.totalGobblersBalance;
    }
}
