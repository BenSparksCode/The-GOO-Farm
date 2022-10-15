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
    // Farm users
    address constant ALICE = address(0xaaa);
    address constant BOB = address(0xbbb);
    address constant CHAD = address(0xccc);
    // Non-farm users
    address constant N_ALICE = address(0xfaaa);
    address constant N_BOB = address(0xfbbb);
    address constant N_CHAD = address(0xfccc);

    address constant TREASURY = address(0x777);
    uint256 constant GOBBLER_CUT = 0.5e18;

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
        farmController = new FarmController(GOBBLER_CUT, 0, TREASURY);
        gobblerPen = new GobblerPen(IArtGobblers(predictArtGobblers), predictGooFarm);

        gooFarm = new GooFarm(
            goo,
            IFarmController(predictFarmController),
            IArtGobblers(predictArtGobblers),
            IGobblerPen(predictGobblerPen)
        );

        // Mint gobblers to users
        // Farm users
        vm.prank(ALICE);
        artGobblers.mintGobbler(aliceGobbler1Mul);
        vm.prank(BOB);
        artGobblers.mintGobbler(bobGobbler1Mul);
        vm.prank(CHAD);
        artGobblers.mintGobbler(chadGobbler1Mul);
        // Non-farm users, but start with same assets
        vm.prank(N_ALICE);
        artGobblers.mintGobbler(aliceGobbler1Mul);
        vm.prank(N_BOB);
        artGobblers.mintGobbler(bobGobbler1Mul);
        vm.prank(N_CHAD);
        artGobblers.mintGobbler(chadGobbler1Mul);
        // All users start with 1 yr of GOO
        vm.warp(block.timestamp + 365 days);
    }

    /*//////////////////////////////////////////////////////////////
                                NEGATIVES
    //////////////////////////////////////////////////////////////*/

    // TODO test any standard ERC4626 behaviour should be disabled if needed

    /*//////////////////////////////////////////////////////////////
                                POSITIVES
    //////////////////////////////////////////////////////////////*/

    function testGobblersDepositedAsExpected() public {
        uint256 gobblerId = 1;
        uint256[] memory aGobblers = new uint256[](1);
        aGobblers[0] = gobblerId;

        assertEq(artGobblers.ownerOf(gobblerId), ALICE);
        vm.expectRevert(bytes("NOT_MINTED"));
        assertEq(gobblerPen.ownerOf(gobblerId), address(0));

        depositEverything(ALICE, aGobblers);

        assertEq(gobblerPen.ownerOf(gobblerId), ALICE);
        assertEq(artGobblers.ownerOf(gobblerId), address(gooFarm));
    }

    /*//////////////////////////////////////////////////////////////
                                SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function testFarmNonfarmProductionParity() public {
        uint256[] memory aGobblers = new uint256[](1);
        aGobblers[0] = 1;

        console.log("Alice: \t", getTotalGooBalance(ALICE));
        console.log("NAlice: \t", getTotalGooBalance(N_ALICE));

        assertEq(artGobblers.gooBalance(ALICE), artGobblers.gooBalance(N_ALICE));
        assertEq(artGobblers.getUserEmissionMultiple(ALICE), artGobblers.getUserEmissionMultiple(N_ALICE));

        depositEverything(ALICE, aGobblers);

        // >> 1 year
        vm.warp(block.timestamp + 365 days);

        console.log("Alice: \t", getTotalGooBalance(ALICE) + getGobblersGooInFarm(aGobblers));
        console.log("NAlice: \t", getTotalGooBalance(N_ALICE));
    }

    /*//////////////////////////////////////////////////////////////
                                TEST UTILS
    //////////////////////////////////////////////////////////////*/

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
        console.log("normal goo", normalBalance, "goo in farm", farmBalance);
        gooBalance = normalBalance + farmBalance;
    }

    function getGobblersGooInFarm(uint256[] memory gobblerIDs) internal view returns (uint256 gooBalance) {
        for (uint256 i = 0; i < gobblerIDs.length; i++) {
            gooBalance += gooFarm.gooEarnedByGobbler(gobblerIDs[i]);
        }
    }

    // Deposits all a users gobblers and goo to the farm
    function depositEverything(address user, uint256[] memory gobblerIDs) internal {
        vm.startPrank(user);
        artGobblers.approveGoo({spender: address(gooFarm), amount: type(uint256).max});
        artGobblers.setApprovalForAll({operator: address(gooFarm), approved: true});
        gooFarm.depositGobblers({to: user, from: user, gobblerIDs: gobblerIDs});
        uint256 erc20GooBal = goo.balanceOf(user);
        if (erc20GooBal > 0) artGobblers.addGoo(erc20GooBal);
        gooFarm.deposit(artGobblers.gooBalance(user), user, false);
        vm.stopPrank();
    }

    // Withdraws all a users gobblers and goo from the farm
    function withdrawEverything(address user, uint256[] memory gobblerIDs) internal {
        vm.startPrank(user);
        gooFarm.withdrawGobblers({to: user, gobblerIDs: gobblerIDs});
        // uint256 erc20GooBal = goo.balanceOf(user);
        // if (erc20GooBal > 0) artGobblers.addGoo(erc20GooBal);
        // gooFarm.deposit(artGobblers.gooBalance(user), user, false);
        vm.stopPrank();
    }
}
