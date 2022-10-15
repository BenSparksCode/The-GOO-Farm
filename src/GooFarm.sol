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
// TODO make sure incompatible functions from 4626 are blocked here
// TODO Make receipt NFT enumerable to iterate through all staked gobblers

contract GooFarm is ERC4626, Ownable2Step, ERC721TokenReceiver {
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    uint256 internal constant SCALE = 1e18;

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
        // Prev rewards not claimable relative to `accGooPerGobblerShare` (`rewardDebt` in MasterChef PoolStaker)
        uint256 gobblerGooDebtPerShare;
        // Note: No need to store gobblerMultiplier as it doesn't change and can be read on withdraw
    }
    mapping(uint256 => StakedGobbler) public stakedGobblers; // nftID -> StakedGobbler

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

    /*//////////////////////////////////////////////////////////////
                            GOBBLER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice External function for depositing gobblers.
    /// @param from Account to deposit gobblers from.
    /// @param to Account to send receipt tokens to.
    /// @param gobblerIDs Array of gobbler IDs to deposit.
    function depositGobblers(
        address from,
        address to,
        uint256[] calldata gobblerIDs
    ) external {
        uint256 len = gobblerIDs.length;
        uint256 i;
        for (i; i < len; ) {
            _depositGobbler(from, to, gobblerIDs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @notice External function for withdrawing gobblers,
    /// and receiving any accrued goo rewards.
    /// @param to Account to send gobblers and goo to.
    /// @param gobblerIDs ID of gobbler to withdraw.
    function withdrawGobblers(address to, uint256[] calldata gobblerIDs) external {
        uint256 len = gobblerIDs.length;
        uint256 i;
        for (i; i < len; ) {
            _withdrawGobbler(to, gobblerIDs[i]);
            unchecked {
                ++i;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            GOO FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    // TODO support ERC20 goo with optional flag
    function deposit(
        uint256 assets,
        address receiver,
        bool usingERC20
    ) public returns (uint256 shares) {
        _updateBalances();

        // Check for rounding error since we round down in previewDeposit.
        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _depositGoo(msg.sender, assets, usingERC20);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // TODO support ERC20 goo with optional flag
    function mint(uint256 shares, address receiver) public override returns (uint256 assets) {
        _updateBalances();

        assets = previewMint(shares); // No need to check for rounding error, previewMint rounds up.

        _depositGoo(msg.sender, assets, true);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    // TODO support ERC20 goo with optional flag
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

        uint256 fee;
        uint256 netShares;

        if (farmController.protocolFee() > 0) {
            (fee, netShares) = farmController.calculateProtocolFee(shares);
        } else {
            (fee, netShares) = (0, shares);
        }

        // Calculate new assets recieved after share fee cut
        assets = previewRedeem(netShares);

        _burn(owner, netShares);

        if (fee > 0) transferFrom(owner, farmController.treasury(), fee);

        // TODO update to include fee
        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        _withdrawGoo(receiver, assets, false); // TODO consider erc20 flag
    }

    // TODO support ERC20 goo with optional flag
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

        stakedGobblers[gobblerID].gobblerGooDebtPerShare = accGooPerGobblerShare;

        // TODO add event
    }

    /// @notice Internal logic for withdrawing a gobbler NFT,
    /// burning the associated xGobbler NFT share,
    /// and receiving any accrued goo rewards.
    /// @param to Account to send gobbler and goo to.
    /// @param gobblerID ID of gobbler to withdraw.
    function _withdrawGobbler(address to, uint256 gobblerID) internal {
        if (gobblerPen.ownerOf(gobblerID) != msg.sender) revert NotGobblerOwner();

        uint256 gobblerMultiple = artGobblers.getGobblerEmissionMultiple(gobblerID);
        uint256 totalFarmMultiple = artGobblers.getUserEmissionMultiple(address(this));

        _updateBalances();

        uint256 gooToWithdraw = (gobblerMultiple * (accGooPerGobblerShare - stakedGobblers[gobblerID].gobblerGooDebtPerShare)) /
            SCALE;

        // Update global farm variables
        lastFarmGooBalance -= gooToWithdraw;
        lastGobblersGooBalance -= gooToWithdraw;
        delete stakedGobblers[gobblerID];

        // Burn receipt NFT
        gobblerPen.burnForGooFarm(gobblerID);

        // Send gobbler
        artGobblers.transferFrom(address(this), to, gobblerID);

        // Send goo
        artGobblers.transferGoo(to, gooToWithdraw);

        // TODO add event
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
            asset.transferFrom(from, address(this), gooAmount);
            artGobblers.addGoo(gooAmount);
        } else {
            // TODO update when ArtGobblers PR is finalized
            artGobblers.transferGooFrom(from, address(this), gooAmount);
        }
    }

    function _withdrawGoo(
        address to,
        uint256 gooAmount,
        bool usingERC20
    ) internal {
        if (usingERC20) {
            artGobblers.removeGoo(gooAmount);
            asset.transfer(to, gooAmount);
        } else {
            // TODO update when ArtGobblers PR is finalized
            artGobblers.transferGoo(to, gooAmount);
        }
    }

    // This balance update should be called before any deposits or withdraws
    function _updateBalances() internal {
        if (lastUpdateTime == block.timestamp) return;
        uint256 totalFarmMultiple = artGobblers.getUserEmissionMultiple(address(this));
        uint256 currentTotalGoo = artGobblers.gooBalance(address(this));

        if (currentTotalGoo == 0) return;
        uint256 totalBalanceDiff = currentTotalGoo - lastFarmGooBalance;

        uint256 gobblerCut = farmController.calculateGobblerCut(totalBalanceDiff);

        // Increase goo for gobbler stakers - MasterChef logic
        // Will revert if Goo deposited with no Gobblers in farm - intended
        accGooPerGobblerShare = accGooPerGobblerShare + ((gobblerCut * SCALE) / totalFarmMultiple);

        lastFarmGooBalance = currentTotalGoo;
        lastGobblersGooBalance += gobblerCut;
        lastUpdateTime = block.timestamp;
    }

    function gooEarnedByGobbler(uint256 gobblerID) public view returns (uint256) {
        // If gobbler not in farm, zero goo earned
        if (artGobblers.ownerOf(gobblerID) != address(this)) return 0;

        uint256 gobblerMultiple = artGobblers.getGobblerEmissionMultiple(gobblerID);
        uint256 totalFarmMultiple = artGobblers.getUserEmissionMultiple(address(this));

        if (lastUpdateTime == block.timestamp) {
            return (gobblerMultiple * lastFarmGooBalance) / totalFarmMultiple;
        } else {
            uint256 newGobblerGooPerShare = (farmController.calculateGobblerCut(
                artGobblers.gooBalance(address(this)) - lastFarmGooBalance
            ) * SCALE) / totalFarmMultiple;
            return
                (gobblerMultiple *
                    (accGooPerGobblerShare + newGobblerGooPerShare - stakedGobblers[gobblerID].gobblerGooDebtPerShare)) / SCALE;
        }
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
