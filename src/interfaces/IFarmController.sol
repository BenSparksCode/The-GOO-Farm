// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

interface IFarmController {
    // EVENTS
    event ProtocolFeeUpdated(uint256 oldFee, uint256 newFee);
    event GobblersCutUpdated(uint256 oldCut, uint256 newCut);
    event TreasuryUpdated(address oldTreasury, address newTreasury);

    // ERRORS
    error GreaterThanScale();
    error NoZeroAddressAllowed();

    // WRITE FUNCTIONS
    function setProtocolFee(uint256 newFee) external;

    function setGobblersCut(uint256 newCut) external;

    function setTreasury(address newTreasury) external;

    // VIEW FUNCTIONS
    function gobblersCut() external returns (uint256);

    function protocolFee() external returns (uint256);

    function treasury() external returns (address);
}
