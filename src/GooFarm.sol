// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

contract GooFarm is ERC4626 {
    constructor(ERC20 goo) ERC4626(goo, "Farmed Goo", "xGOO") {}

    // Returns total GOO (less Gobbler and protocol fees) in the protocol
    function totalAssets() public view override returns (uint256) {
        // TODO
        return 1;
    }
}
