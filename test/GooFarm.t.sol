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
    struct Balances {
        uint256 goo;
        uint256 xGoo;
        uint256[] Gobblers;
        uint256[] xGobblers;
    }

    Utilities internal utils;

    address constant OWNER = address(0x0123);
    // Farm users
    address constant ALICE = address(0xaaa);
    address constant BOB = address(0xbbb);
    address constant CHAD = address(0xccc);

    // Non-farm users
    address constant N_ALICE = address(0xfaaa);
    address constant N_BOB = address(0xfbbb);
    address constant N_CHAD = address(0xfccc);

    uint256 aliceGobbler1Mul = 69;
    uint256 bobGobbler1Mul = 420;
    uint256 chadGobbler1Mul = 1337;

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

        // Mint gobblers to users
        vm.prank(ALICE);
        artGobblers.mintGobbler(aliceGobbler1Mul);
        vm.prank(BOB);
        artGobblers.mintGobbler(bobGobbler1Mul);
        vm.prank(CHAD);
        artGobblers.mintGobbler(chadGobbler1Mul);
        // All users start with 1 yr of GOO
        vm.warp(block.timestamp + 365 days);
    }

    function testGooAndGobblersDeposit() public {
        uint256 gooBalance;
        uint256[] memory gobblerIDs = new uint256[](1);
        gobblerIDs[0] = 1;

        // Approve goo, approve gobblers, deposit
        vm.startPrank(ALICE);
        artGobblers.approveGoo({spender: address(gooFarm), amount: type(uint256).max});
        artGobblers.setApprovalForAll({operator: address(gooFarm), approved: true});
        gooBalance = artGobblers.gooBalance(ALICE);
        assertEq(ALICE, artGobblers.ownerOf(gobblerIDs[0]));
        (address owner, , ) = artGobblers.getGobblerData(1);

        gooFarm.depositGooOrGobblers({gooAmount: gooBalance, gobblerIDs: gobblerIDs, useERC20Goo: false});
        vm.stopPrank();
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

    // Compare total goo between 2 users
    // Return difference (can be negative if lower had a higher balance)
    function compareUsersGoo(address user1, address user2)
        internal
        view
        returns (
            int256 difference,
            uint256 user1Total,
            uint256 user2Total
        )
    {
        user1Total = getTotalGooBalance(user1);
        user2Total = getTotalGooBalance(user2);
        difference = int256(user1Total) - int256(user2Total);
    }

    function getTotalGooBalance(address user) internal view returns (uint256 gooBalance) {
        uint256 normalBalance = artGobblers.gooBalance(user);
        uint256 farmBalance = gooFarm.convertToAssets(gooFarm.balanceOf(user));
        gooBalance = normalBalance + farmBalance;
    }
}
