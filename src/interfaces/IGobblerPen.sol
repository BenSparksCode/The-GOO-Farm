// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IGobblerPen {
    // WRITE FUNCTIONS
    function mintForGooFarm(address to, uint256 id) external;

    function burnForGooFarm(uint256 id) external;

    // VIEW FUNCTIONS
}
