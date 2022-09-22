// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {IFarmController} from "./interfaces/IFarmController.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

contract FarmController is Ownable2Step, IFarmController {
    uint256 public constant SCALE = 1e18;
    uint256 public gobblersCut;
    uint256 public protocolFee;
    address public treasury;

    constructor() {}

    // VIEW FUNCTIONS

    function calculateProtocolFee(uint256 _amount) public returns (uint256 fee, uint256 netAmount) {
        fee = (protocolFee * _amount) / SCALE;
        netAmount = _amount - fee;
    }

    function calculateGobblerCut(uint256 _amount) public returns (uint256 gobblerCut, uint256 netAmount) {
        gobblerCut = (gobblersCut * _amount) / SCALE;
        netAmount = _amount - gobblerCut;
    }

    // OWNER FUNCTIONS

    function setProtocolFee(uint256 newFee) public onlyOwner {
        if (newFee + gobblersCut > SCALE) revert GreaterThanScale();

        uint256 oldFee = protocolFee;
        protocolFee = newFee;

        emit ProtocolFeeUpdated(oldFee, newFee);
    }

    function setGobblersCut(uint256 newCut) public onlyOwner {
        if (newCut + protocolFee > SCALE) revert GreaterThanScale();

        uint256 oldCut = gobblersCut;
        gobblersCut = newCut;

        emit GobblersCutUpdated(oldCut, newCut);
    }

    function setTreasury(address newTreasury) public onlyOwner {
        if (newTreasury == address(0)) revert NoZeroAddressAllowed();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }
}