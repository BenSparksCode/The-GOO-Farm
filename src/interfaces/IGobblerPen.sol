// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IERC721} from "openzeppelin/interfaces/IERC721.sol";

interface IGobblerPen is IERC721 {
    // WRITE FUNCTIONS
    function mintForGooFarm(address to, uint256 id) external;

    function burnForGooFarm(uint256 id) external;

    // VIEW FUNCTIONS
}
