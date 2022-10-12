// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/Test.sol";

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

    // EXTERNAL CONTRACTS
    IFarmController public farmController;
    IArtGobblers public artGobblers;
    IGobblerPen public gobblerPen;

    // FARM ACCOUNTING
    uint256 public lastUpdateTime; // Last time these global goo vars were updated
    uint256 public lastFarmGooBalance; // Goo across the entire farm
    uint256 public lastGobblersGooBalance; // Goo that belongs to Gobbler stakers

    // GOBBLER ACCOUNTING
    uint256 internal accGooPerGobblerShare;
    struct StakedGobbler {
        uint256 gobblerMultiplier; // Multiplier staked/contributed (`amount` in MasterChef PoolStaker)
        uint256 gobblerGooDebt; // Amount deducted from `accGooPerGobblerShare` (`rewardDebt` in MasterChef PoolStaker)
    }
    mapping(uint256 => StakedGobbler) public stakedGobblers; // nftID -> StakedGobbler

    // TODO TEST DATA - REMOVE after refactor
    struct GobblerStaking {
        uint256 lastIndex;
    }
    uint256 internal gobblerSharesPerMultipleIndex = 0;
    mapping(uint256 => GobblerStaking) public gobblerStakingMap; // gobblerID to 'lastIndex'
    // END OF TEST DATA

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
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256 shares) {
        _updateBalances();

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _depositGoo(msg.sender, assets, true);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        _updateBalances();

        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        _depositGoo(msg.sender, assets, true);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // Gives you more control than the ERC4626 functions for GOO
    // Can do goo directly in emissions mode
    function depositGooOrGobblers(
        uint256 gooAmount,
        uint256[] calldata gobblerIDs,
        bool useERC20Goo
    ) public {
        _updateBalances();

        // Handle Goo deposit
        if (gooAmount != 0) {
            uint256 shares = previewDeposit(gooAmount);
            _depositGoo(msg.sender, gooAmount, useERC20Goo);
            _mint(msg.sender, shares);
        }

        uint256 len = gobblerIDs.length;
        if (len > 0) {
            uint256 i;
            for (i; i < len; ++i) {
                _depositGobbler(msg.sender, msg.sender, gobblerIDs[i]);
            }
        }
    }

    function withdrawGobblers(uint256[] calldata gobblerIDs) public {
        _updateBalances();

        uint256 len = gobblerIDs.length;
        if (len > 0) {
            uint256 i;
            for (i; i < len; ++i) {
                _withdrawGobbler(msg.sender, gobblerIDs[i]);
            }
        }
    }

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

        _updateBalances();

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

        _updateBalances();

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

        gobblerStakingMap[gobblerID].lastIndex = gobblerSharesPerMultipleIndex;

        // gobblerData[gobblerID].lastUpdatedTimestamp = block.timestamp;
        // gobblerData[gobblerID].totalGobblersBalanceAtDeposit = lastGobblersGooBalance;
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

        uint256 gooShares = ((gobblerSharesPerMultipleIndex - gobblerStakingMap[gobblerID].lastIndex) * gobblerMultiple) / 1e18;

        uint256 gooRewards;
        if (gooShares > 0) {
            gooRewards = previewRedeem(gooShares) / 1e18;

            lastFarmGooBalance -= gooRewards;
            lastGobblersGooBalance -= gooRewards;
        }

        delete gobblerData[gobblerID];

        // OLD Attempt - delete
        // uint256 gobblerGooSinceDeposit = lastGobblersGooBalance - gobblerData[gobblerID].totalGobblersBalanceAtDeposit;
        // uint256 gooRewards = (gobblerMultiple * gobblerGooSinceDeposit) / artGobblers.getUserEmissionMultiple(address(this));

        // Burn receipt NFT
        gobblerPen.burnForGooFarm(gobblerID);

        // Send gobbler
        artGobblers.transferFrom(address(this), to, gobblerID);

        // Send goo
        artGobblers.transferGoo(to, gooRewards);
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
        if (lastUpdateTime == block.timestamp) return;
        uint256 totalFarmMultiple = artGobblers.getUserEmissionMultiple(address(this));
        uint256 currentTotalGoo = artGobblers.gooBalance(address(this));

        if (currentTotalGoo == 0) return;
        uint256 totalBalanceDiff = currentTotalGoo - lastFarmGooBalance;

        uint256 gobblerCut = farmController.calculateGobblerCut(totalBalanceDiff);

        uint256 newGooSharesForGobblers = previewDeposit(gobblerCut);

        if (totalFarmMultiple != 0) gobblerSharesPerMultipleIndex += (newGooSharesForGobblers * 1e18) / totalFarmMultiple;

        lastFarmGooBalance += currentTotalGoo;
        lastGobblersGooBalance += gobblerCut;
        lastUpdateTime = block.timestamp;
    }

    // NOTE: Misleading function name
    // Part of the ERC4626 vault which is only for xGOO holders
    // This reports the total goo attributable to xGOO holders
    // But excludes any goo attributable to xGobbler holders
    function totalAssets() public view override returns (uint256) {
        // We can skip the external contract reads if farmData was updated in this block
        if (lastUpdateTime == block.timestamp) {
            return lastFarmGooBalance - lastGobblersGooBalance;
        } else {
            return
                (lastFarmGooBalance - lastGobblersGooBalance) +
                farmController.calculateGooCut(artGobblers.gooBalance(address(this)) - lastFarmGooBalance);
        }
    }
}
