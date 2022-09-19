// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "forge-std/Test.sol";

import {GooFarm} from "../src/GooFarm.sol";
import {MockGoo} from "../src/mocks/MockGoo.sol";

contract GooFarmTest is Test {
    address constant OWNER = address(0x0123);
    address constant ALICE = address(0xaaa);
    address constant BOB = address(0xbbb);

    GooFarm gooFarm;
    MockGoo goo;

    function setUp() public {
        vm.startPrank(ALICE);
        goo = new MockGoo();
        vm.stopPrank();
        gooFarm = new GooFarm(goo);
    }

    function testFunc1() public {
        logBalances(ALICE);

        vm.startPrank(ALICE);
        goo.approve(address(gooFarm), type(uint256).max);
        gooFarm.deposit(1e18, ALICE);
        vm.stopPrank();

        logBalances(ALICE);
    }

    // TEST UTILS

    function logBalances(address user) public {
        console.log("GOO balance", goo.balanceOf(user));
        console.log("xGOO balance", gooFarm.balanceOf(user));
    }
}
