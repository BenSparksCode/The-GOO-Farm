// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {LibString} from "solmate/utils/LibString.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";
import {toWadUnsafe, toDaysWadUnsafe} from "solmate/utils/SignedWadMath.sol";

import {LibGOO} from "goo-issuance/LibGOO.sol";

import {GobblersERC721} from "./GobblersERC721.sol";

import {Goo} from "./Goo.sol";

contract ArtGobblers is GobblersERC721 {
    using LibString for uint256;
    using FixedPointMathLib for uint256;

    /// @notice The address of the Goo ERC20 token contract.
    Goo public immutable goo;

    /// @notice Base URI for minted gobblers.
    string public BASE_URI = "https://www.paradigm.xyz/2022/09/artgobblers";

    /// @notice Id of the most recently minted non legendary gobbler.
    /// @dev Will be 0 if no non legendary gobblers have been minted yet.
    uint128 public currentNonLegendaryId;

    mapping(address => mapping(address => uint256)) public gooAllowance;

    event GooBalanceUpdated(address indexed user, uint256 newGooBalance);

    event GooTransfer(address indexed from, address indexed to, uint256 gooAmount);

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets VRGDA parameters, mint config, relevant addresses, and URIs.
    /// @param _goo Address of the Goo contract.
    constructor(Goo _goo) GobblersERC721("Art Gobblers", "GOBBLER") {
        goo = _goo;
    }

    /*//////////////////////////////////////////////////////////////
                              MINTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // Test function to mint a new Gobbler with a specified multiplier.
    // No GOO or whitelist stuff required.
    function mintGobbler(uint256 multiplier) public returns (uint256 gobblerId) {
        // TODO add multiplier setting stuff

        gobblerId = ++currentNonLegendaryId;
        _mint(msg.sender, gobblerId);

        // Multiple logic from revealGobblers
        getGobblerData[gobblerId].idx = uint64(gobblerId);
        getGobblerData[gobblerId].emissionMultiple = uint32(multiplier);

        // Update the user data for the owner of the current id.
        // getUserData[currentIdOwner].lastBalance = uint128(gooBalance(currentIdOwner)); GOO balance not affected
        getUserData[msg.sender].lastTimestamp = uint64(block.timestamp);
        getUserData[msg.sender].emissionMultiple += uint32(multiplier);
        getUserData[msg.sender].gobblersOwned++;
    }

    /*//////////////////////////////////////////////////////////////
                                URI LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns a token's URI if it has been minted.
    /// @param gobblerId The id of the token to get the URI for.
    function tokenURI(uint256 gobblerId) public view virtual override returns (string memory) {
        return BASE_URI;
    }

    /*//////////////////////////////////////////////////////////////
                                GOO LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculate a user's virtual goo balance.
    /// @param user The user to query balance for.
    function gooBalance(address user) public view returns (uint256) {
        // Compute the user's virtual goo balance by leveraging LibGOO.
        // prettier-ignore
        return LibGOO.computeGOOBalance(
            getUserData[user].emissionMultiple,
            getUserData[user].lastBalance,
            uint256(toDaysWadUnsafe(block.timestamp - getUserData[user].lastTimestamp))
        );
    }

    /// @notice Add goo to your emission balance,
    /// burning the corresponding ERC20 balance.
    /// @param gooAmount The amount of goo to add.
    function addGoo(uint256 gooAmount) external {
        // Burn goo being added to gobbler.
        goo.burnForGobblers(msg.sender, gooAmount);

        // Increase msg.sender's virtual goo balance.
        updateUserGooBalance(msg.sender, gooAmount, GooBalanceUpdateType.INCREASE);
    }

    /// @notice Remove goo from your emission balance, and
    /// add the corresponding amount to your ERC20 balance.
    /// @param gooAmount The amount of goo to remove.
    function removeGoo(uint256 gooAmount) external {
        // Decrease msg.sender's virtual goo balance.
        updateUserGooBalance(msg.sender, gooAmount, GooBalanceUpdateType.DECREASE);

        // Mint the corresponding amount of ERC20 goo.
        goo.mintForGobblers(msg.sender, gooAmount);
    }

    /// @notice Approve a spender account to transfer internal goo on user's behalf.
    /// @param spender The spender account being approved.
    /// @param amount The amount of goo to approve spender for.
    function approveGoo(address spender, uint256 amount) public virtual returns (bool) {
        gooAllowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    /// @notice Transfer goo directly from your emission balance,
    /// to a recipient's emission balance.
    /// @param to The goo recipient's address.
    /// @param gooAmount The amount of goo to transfer.
    function transferGoo(address to, uint256 gooAmount) external returns (bool) {
        // Will revert due to underflow if we're decreasing by more than the user's current balance.
        uint256 fromUpdatedBalance = gooBalance(msg.sender) - gooAmount;
        getUserData[msg.sender].lastBalance = uint128(fromUpdatedBalance);
        getUserData[msg.sender].lastTimestamp = uint64(block.timestamp);

        // Don't need to do checked addition in the increase case.
        uint256 toUpdatedBalance;
        unchecked {
            toUpdatedBalance = gooBalance(to) + gooAmount;
            getUserData[to].lastBalance = uint128(toUpdatedBalance);
            getUserData[to].lastTimestamp = uint64(block.timestamp);
        }

        emit GooBalanceUpdated(msg.sender, fromUpdatedBalance);
        emit GooBalanceUpdated(to, toUpdatedBalance);
        emit GooTransfer(msg.sender, to, gooAmount);

        return true;
    }

    /// @notice Transfer goo directly from a user's emission balance,
    /// to a recipient's emission balance.
    /// @param from The goo sender's address.
    /// @param to The goo recipient's address.
    /// @param gooAmount The amount of goo to transfer.
    function transferGooFrom(
        address from,
        address to,
        uint256 gooAmount
    ) external returns (bool) {
        uint256 allowed = (from == msg.sender) ? type(uint256).max : gooAllowance[from][msg.sender];
        if (allowed != type(uint256).max) gooAllowance[from][msg.sender] = allowed - gooAmount;

        // Will revert due to underflow if we're decreasing by more than the user's current balance.
        uint256 fromUpdatedBalance = gooBalance(from) - gooAmount;
        getUserData[from].lastBalance = uint128(fromUpdatedBalance);
        getUserData[from].lastTimestamp = uint64(block.timestamp);

        // Don't need to do checked addition in the increase case.
        uint256 toUpdatedBalance;
        unchecked {
            toUpdatedBalance = gooBalance(to) + gooAmount;
            getUserData[to].lastBalance = uint128(toUpdatedBalance);
            getUserData[to].lastTimestamp = uint64(block.timestamp);
        }

        emit GooBalanceUpdated(from, fromUpdatedBalance);
        emit GooBalanceUpdated(to, toUpdatedBalance);
        emit GooTransfer(from, to, gooAmount);

        return true;
    }

    /// @dev An enum for representing whether to
    /// increase or decrease a user's goo balance.
    enum GooBalanceUpdateType {
        INCREASE,
        DECREASE
    }

    /// @notice Update a user's virtual goo balance.
    /// @param user The user whose virtual goo balance we should update.
    /// @param gooAmount The amount of goo to update the user's virtual balance by.
    /// @param updateType Whether to increase or decrease the user's balance by gooAmount.
    function updateUserGooBalance(
        address user,
        uint256 gooAmount,
        GooBalanceUpdateType updateType
    ) internal {
        // Will revert due to underflow if we're decreasing by more than the user's current balance.
        // Don't need to do checked addition in the increase case, but we do it anyway for convenience.
        uint256 updatedBalance = updateType == GooBalanceUpdateType.INCREASE
            ? gooBalance(user) + gooAmount
            : gooBalance(user) - gooAmount;

        // Snapshot the user's new goo balance with the current timestamp.
        getUserData[user].lastBalance = uint128(updatedBalance);
        getUserData[user].lastTimestamp = uint64(block.timestamp);

        emit GooBalanceUpdated(user, updatedBalance);
    }

    /*//////////////////////////////////////////////////////////////
                          CONVENIENCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Convenience function to get emissionMultiple for a gobbler.
    /// @param gobblerId The gobbler to get emissionMultiple for.
    function getGobblerEmissionMultiple(uint256 gobblerId) external view returns (uint256) {
        return getGobblerData[gobblerId].emissionMultiple;
    }

    /// @notice Convenience function to get emissionMultiple for a user.
    /// @param user The user to get emissionMultiple for.
    function getUserEmissionMultiple(address user) external view returns (uint256) {
        return getUserData[user].emissionMultiple;
    }

    /*//////////////////////////////////////////////////////////////
                              ERC721 LOGIC
    //////////////////////////////////////////////////////////////*/

    function transferFrom(
        address from,
        address to,
        uint256 id
    ) public override {
        require(from == getGobblerData[id].owner, "WRONG_FROM");

        require(to != address(0), "INVALID_RECIPIENT");

        require(msg.sender == from || isApprovedForAll[from][msg.sender] || msg.sender == getApproved[id], "NOT_AUTHORIZED");

        delete getApproved[id];

        getGobblerData[id].owner = to;

        unchecked {
            uint32 emissionMultiple = getGobblerData[id].emissionMultiple; // Caching saves gas.

            // We update their last balance before updating their emission multiple to avoid
            // penalizing them by retroactively applying their new (lower) emission multiple.
            getUserData[from].lastBalance = uint128(gooBalance(from));
            getUserData[from].lastTimestamp = uint64(block.timestamp);
            getUserData[from].emissionMultiple -= emissionMultiple;
            getUserData[from].gobblersOwned -= 1;

            // We update their last balance before updating their emission multiple to avoid
            // overpaying them by retroactively applying their new (higher) emission multiple.
            getUserData[to].lastBalance = uint128(gooBalance(to));
            getUserData[to].lastTimestamp = uint64(block.timestamp);
            getUserData[to].emissionMultiple += emissionMultiple;
            getUserData[to].gobblersOwned += 1;
        }

        emit Transfer(from, to, id);
    }
}
