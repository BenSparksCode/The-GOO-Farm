// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Test.sol";
import {Utilities} from "./utils/Utilities.sol";

import {GooFarm} from "../src/GooFarm.sol";
import {ArtGobblers} from "./mocks/ArtGobblers.sol";
import {Goo} from "./mocks/Goo.sol";

contract GooFarmTest is Test {
    Utilities internal utils;

    address constant OWNER = address(0x0123);
    address constant ALICE = address(0xaaa);
    address constant BOB = address(0xbbb);

    GooFarm gooFarm;
    ArtGobblers artGobblers;
    Goo goo;

    function setUp() public {
        utils = new Utilities();

        address predictedArtGobblersAddr = utils.predictContractAddress(address(this), 1);
        goo = new Goo(predictedArtGobblersAddr);
        artGobblers = new ArtGobblers(goo);
        gooFarm = new GooFarm(goo);

        console.log(address(artGobblers), predictedArtGobblersAddr);

        deal(address(goo), ALICE, 100e18);
        deal(address(goo), BOB, 100e18);
    }

    function testFunc1() public {
        logBalances(ALICE, "Alice");
        logBalances(BOB, "Bob");

        vm.startPrank(ALICE);
        goo.approve(address(gooFarm), type(uint256).max);
        gooFarm.deposit(10e18, ALICE);
        vm.stopPrank();

        logBalances(ALICE, "Alice");
        logBalances(BOB, "Bob");
    }

    // TEST UTILS

    function logBalances(address user, string memory name) public {
        console.log(name, ":");
        console.log("GOO balance\t", goo.balanceOf(user));
        console.log("xGOO balance\t", gooFarm.balanceOf(user));
        console.log("\n");
    }
}
