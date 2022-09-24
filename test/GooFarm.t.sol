// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import {GooFarm} from "../src/GooFarm.sol";
import {MockGoo} from "./mocks/MockGoo.sol";

contract GooFarmTest is Test {
    address constant OWNER = address(0x0123);
    address constant ALICE = address(0xaaa);
    address constant BOB = address(0xbbb);

    GooFarm gooFarm;
    MockGoo goo;

    function setUp() public {
        goo = new MockGoo();
        gooFarm = new GooFarm(goo);

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
