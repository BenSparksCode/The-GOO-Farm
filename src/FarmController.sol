// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import {IFarmController} from "./interfaces/IFarmController.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

contract FarmController is Ownable2Step, IFarmController {
    uint256 public constant SCALE = 1e18;
    uint256 public gobblersCut;
    uint256 public protocolFee;
    address public treasury;

    constructor(
        uint256 _gobblersCut,
        uint256 _protocolFee,
        address _treasury
    ) {
        if (_treasury == address(0)) revert NoZeroAddressAllowed();
        if (_gobblersCut >= SCALE || _protocolFee >= SCALE) revert MustBeLessThanScale();
        gobblersCut = _gobblersCut;
        protocolFee = _protocolFee;
        treasury = _treasury;

        emit GobblersCutUpdated(0, _gobblersCut);
        emit ProtocolFeeUpdated(0, _protocolFee);
        emit TreasuryUpdated(address(0), _treasury);
    }

    // VIEW FUNCTIONS

    // TODO Consider only returning fee portion
    function calculateProtocolFee(uint256 _amount) public view returns (uint256 fee, uint256 netAmount) {
        fee = (protocolFee * _amount) / SCALE;
        netAmount = _amount - fee;
    }

    // Gobbler cut taken first in updateBalances
    // Protocol fee taken in xGOO later on withdraw/redeem
    function calculateGobblerCut(uint256 _amount) public view returns (uint256 amountForGobblers) {
        amountForGobblers = (gobblersCut * _amount) / SCALE;
    }

    // Returns the share of an amount for xGoo holders, not xGobbler holders
    function calculateGooCut(uint256 _amount) public view returns (uint256 amountForGoo) {
        amountForGoo = ((SCALE - gobblersCut) * _amount) / SCALE;
    }

    // OWNER FUNCTIONS

    function setProtocolFee(uint256 newFee) public onlyOwner {
        if (newFee >= SCALE) revert MustBeLessThanScale();

        uint256 oldFee = protocolFee;
        protocolFee = newFee;

        emit ProtocolFeeUpdated(oldFee, newFee);
    }

    function setGobblersCut(uint256 newCut) public onlyOwner {
        if (newCut >= SCALE) revert MustBeLessThanScale();

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
