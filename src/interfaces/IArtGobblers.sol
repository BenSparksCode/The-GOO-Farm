// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

// TODO add any relevant functions/vars from GobblersERC721

interface IArtGobblers {
    /*//////////////////////////////////////////////////////////////
                                VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function gooBalance(address user) external view returns (uint256);

    function getGobblerEmissionMultiple(uint256 gobblerId) external view returns (uint256);

    function getUserEmissionMultiple(address user) external view returns (uint256);

    function tokenURI(uint256 gobblerId) external view returns (string memory);

    /*//////////////////////////////////////////////////////////////
                        STATE-MODIFYING FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function addGoo(uint256 gooAmount) external;

    function removeGoo(uint256 gooAmount) external;

    function transferGoo(address to, uint256 gooAmount) external returns (bool);

    function transferGooFrom(
        address from,
        address to,
        uint256 gooAmount
    ) external returns (bool);

    // To transfer a Gobbler
    function transferFrom(
        address from,
        address to,
        uint256 id
    ) external;
}
