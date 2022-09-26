// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC20} from "solmate/tokens/ERC20.sol";

// TODO code a valueless gov token

contract GOOF is ERC20 {
    constructor() ERC20("GOO Farm Token", "GOOF", 18) {}
}
