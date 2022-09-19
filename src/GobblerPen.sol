// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC1155} from "solmate/tokens/ERC1155.sol";
import {ERC1155Holder} from "openzeppelin/token/ERC1155/utils/ERC1155Holder.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

// GobblerPen is a modified ERC4626 Vault.
// Instead of ERC20 deposits, it takes ERC1155 NFTs (Gobblers),
// and rewards depositors with shares in proportion to the multiplier of their deposited Gobbler.
contract GobblerPen is ERC20, ERC1155Holder {
    using FixedPointMathLib for uint256;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Deposit(address indexed caller, address indexed owner, uint256 gobblerID, uint256 multiplier, uint256 shares);

    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 gobblerID,
        uint256 multiplier,
        uint256 shares
    );

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    ERC1155 public immutable GOBBLER;

    uint256 public multiplierSum;

    constructor(
        ERC1155 _gobbler,
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol, 18) {
        GOBBLER = _gobbler;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    // TODO consider adding 18 decimals to multiplier for share calculations
    function deposit(uint256 gobblerID, address receiver) public returns (uint256 shares) {
        // Check for rounding error since we round down in previewDeposit.

        uint256 multiplier = getMultiplierOfGobbler(gobblerID);

        require((shares = previewDeposit(multiplier)) != 0, "ZERO_SHARES");

        multiplierSum += multiplier;

        // TODO send to Gooptimizooor.sol instead of here
        GOBBLER.safeTransferFrom(msg.sender, address(this), gobblerID, 1, "");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, gobblerID, multiplier, shares);
    }

    function withdraw(
        uint256 gobblerID,
        address receiver,
        address owner
    ) public returns (uint256 shares) {
        uint256 multiplier = getMultiplierOfGobbler(gobblerID);

        shares = previewWithdraw(multiplier); // No need to check for rounding error, previewWithdraw rounds up.

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max) allowance[owner][msg.sender] = allowed - shares;
        }

        multiplierSum -= multiplier;

        _burn(owner, shares);

        // TODO send from Gooptimizooor.sol instead of here
        // TODO but do this by first withdrawing GOO to protocol
        GOBBLER.safeTransferFrom(address(this), receiver, gobblerID, 1, "");

        emit Withdraw(msg.sender, receiver, owner, gobblerID, multiplier, shares);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    // Returns sum of multipliers of Gobblers in the pen
    // New shares are issued in proportion to this figure
    function totalAssets() public view returns (uint256) {
        return multiplierSum;
    }

    // Modified from ERC4626.
    // assets represents new multiplier number of Gobbler deposited.
    function convertToShares(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivDown(supply, totalAssets());
    }

    function convertToAssets(uint256 shares) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? shares : shares.mulDivDown(totalAssets(), supply);
    }

    function previewDeposit(uint256 assets) public view virtual returns (uint256) {
        return convertToShares(assets);
    }

    function previewWithdraw(uint256 assets) public view virtual returns (uint256) {
        uint256 supply = totalSupply; // Saves an extra SLOAD if totalSupply is non-zero.

        return supply == 0 ? assets : assets.mulDivUp(supply, totalAssets());
    }

    function getMultiplierOfGobbler(uint256 gobblerID) public view returns (uint256) {
        // TODO implement once Gobbler contract is available
        return 15;
    }
}
