// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {ERC1155} from "solmate/tokens/ERC1155.sol";

contract MockGobbler is ERC1155 {
    constructor() ERC1155() {
        // TODO
    }

    function uri(uint256 id) public view override returns (string memory) {
        return "test.gobbler.com";
    }
}
