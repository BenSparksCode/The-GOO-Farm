// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "forge-std/Test.sol";
import {Utilities} from "./utils/Utilities.sol";

import {Goo} from "./mocks/Goo.sol";
import {ArtGobblers} from "./mocks/ArtGobblers.sol";
import {GooFarm} from "../src/GooFarm.sol";
import {GobblerPen} from "../src/GobblerPen.sol";
import {FarmController} from "../src/FarmController.sol";

import {IFarmController} from "../src/interfaces/IFarmController.sol";
import {IArtGobblers} from "../src/interfaces/IArtGobblers.sol";
import {IGobblerPen} from "../src/interfaces/IGobblerPen.sol";

contract GooFarmTest is Test {
    Utilities internal utils;

    address constant OWNER = address(0x0123);
    address constant ALICE = address(0xaaa);
    address constant BOB = address(0xbbb);

    Goo goo;
    ArtGobblers artGobblers;
    FarmController farmController;
    GobblerPen gobblerPen;
    GooFarm gooFarm;

    function setUp() public {
        utils = new Utilities();

        address predictArtGobblers = utils.predictContractAddress(address(this), 1);
        address predictFarmController = utils.predictContractAddress(address(this), 2);
        address predictGobblerPen = utils.predictContractAddress(address(this), 3);
        address predictGooFarm = utils.predictContractAddress(address(this), 4);

        goo = new Goo(predictArtGobblers);
        artGobblers = new ArtGobblers(goo);
        farmController = new FarmController();
        gobblerPen = new GobblerPen(IArtGobblers(predictArtGobblers), predictGooFarm);

        gooFarm = new GooFarm(
            goo,
            IFarmController(predictFarmController),
            IArtGobblers(predictArtGobblers),
            IGobblerPen(predictGobblerPen)
        );

        // deal(address(goo), ALICE, 100e18);
        // deal(address(goo), BOB, 100e18);
    }

    function testBasicGobblerMint() public {
        uint256 aliceMul = 10;
        uint256 bobMul = 20;
        vm.prank(ALICE);
        artGobblers.mintGobbler(aliceMul);
        vm.prank(BOB);
        artGobblers.mintGobbler(bobMul);

        logBalances(ALICE, "Alice");
        logBalances(BOB, "Bob");

        // Both grow GOO over 1 year
        vm.warp(block.timestamp + 365 days);

        logBalances(ALICE, "Alice");
        logBalances(BOB, "Bob");

        // Alice withdraws GOO to ERC20, another year passes
        vm.startPrank(ALICE);
        // artGobblers.removeGoo(artGobblers.gooBalance(ALICE));
        artGobblers.removeGoo(artGobblers.gooBalance(ALICE));
        vm.warp(block.timestamp + 365 days);

        logBalances(ALICE, "Alice");
        logBalances(BOB, "Bob");
    }

    // TEST UTILS

    function logBalances(address user, string memory name) public view {
        console.log(name, ":");
        console.log("GOO balance\t", artGobblers.gooBalance(user));
        // console.log("xGOO balance\t", gooFarm.balanceOf(user));
        console.log("Emission Mul\t", artGobblers.getUserEmissionMultiple(user));
        console.log("\n");
    }
}
