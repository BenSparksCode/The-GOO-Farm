// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

contract MockGoo is ERC20 {
    uint256 internal supplyToMint = 1_000_000e18;

    constructor() ERC20("Goo", "GOO", 18) {
        _mint(msg.sender, supplyToMint);
    }
}
