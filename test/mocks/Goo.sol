// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ERC20} from "solmate/tokens/ERC20.sol";

/// token that can be burned and minted by the gobblers contract.
contract Goo is ERC20("Goo", "GOO", 18) {
    /*//////////////////////////////////////////////////////////////
                                ADDRESSES
    //////////////////////////////////////////////////////////////*/

    /// @notice The address of the Art Gobblers contract.
    address public immutable artGobblers;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error Unauthorized();

    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the addresses of relevant contracts.
    /// @param _artGobblers Address of the ArtGobblers contract.
    constructor(address _artGobblers) {
        artGobblers = _artGobblers;
    }

    /*//////////////////////////////////////////////////////////////
                             MINT/BURN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @notice Requires caller address to match user address.
    modifier only(address user) {
        if (msg.sender != user) revert Unauthorized();

        _;
    }

    /// @notice Mint any amount of goo to a user. Can only be called by ArtGobblers.
    /// @param to The address of the user to mint goo to.
    /// @param amount The amount of goo to mint.
    function mintForGobblers(address to, uint256 amount) external only(artGobblers) {
        _mint(to, amount);
    }

    /// @notice Burn any amount of goo from a user. Can only be called by ArtGobblers.
    /// @param from The address of the user to burn goo from.
    /// @param amount The amount of goo to burn.
    function burnForGobblers(address from, uint256 amount) external only(artGobblers) {
        _burn(from, amount);
    }
}
