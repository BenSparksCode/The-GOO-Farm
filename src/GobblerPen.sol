// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC721} from "solmate/tokens/ERC721.sol";
import {ERC721TokenReceiver} from "solmate/tokens/ERC721.sol";

import {IArtGobblers} from "./interfaces/IArtGobblers.sol";

// TODO Big refactor needed here
// Deposited assets are now 721 (use custom Gobbler from ArtGobblers repo)
// Receipt token should be 721 as well
// Rewards tracking needs custom impl - not same as GOO - xGOO relationship
// because multipliers dont grow in vault
// Needs lastRewardsTime and currentRewards per gobbler deposited,
// then underlying rewards to accrue to each gobbler on GOO deposits/withdrawals

// TODO change this
// GobblerPen is a modified ERC4626 Vault.
// Instead of ERC20 deposits, it takes ERC1155 NFTs (Gobblers),
// and rewards depositors with shares in proportion to the multiplier of their deposited Gobbler.
contract GobblerPen is ERC721 {
    IArtGobblers public artGobblers;
    address public gooFarm;

    error OnlyGooFarmAllowed();

    constructor(IArtGobblers _artGobblers, address _gooFarm) ERC721("Gobbler Pen", "xGOBBLER") {
        artGobblers = _artGobblers;
        gooFarm = _gooFarm;
    }

    function mintForGooFarm(address to, uint256 id) external onlyGooFarm {
        _mint(to, id);
    }

    function burnForGooFarm(uint256 id) external onlyGooFarm {
        _burn(id);
    }

    // Returns URI from underlying Gobblers contract
    function tokenURI(uint256 id) public view override returns (string memory) {
        return artGobblers.tokenURI(id);
    }

    modifier onlyGooFarm() {
        if (msg.sender != gooFarm) revert OnlyGooFarmAllowed();
        _;
    }
}
