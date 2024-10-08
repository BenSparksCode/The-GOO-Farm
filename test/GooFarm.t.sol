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

    uint256 aliceGobbler1Mul = 50;
    uint256 bobGobbler1Mul = 150;
    uint256 chadGobbler1Mul = 300;

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
        //Any gobblers deposited at deploy time lose shares in goo earnings
        vm.warp(block.timestamp + 1); // Skip 1 second to avoid this
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

        assertEq(artGobblers.gooBalance(ALICE), artGobblers.gooBalance(N_ALICE));
        assertEq(artGobblers.getUserEmissionMultiple(ALICE), artGobblers.getUserEmissionMultiple(N_ALICE));

        burnGoo(ALICE); // start both users at 0 goo and only multipliers
        burnGoo(N_ALICE);

        depositEverything(ALICE, aGobblers);

        // >> 1 year
        vm.warp(block.timestamp + 365 days);

        withdrawEverything(ALICE, aGobblers);

        assertEq(artGobblers.gooBalance(ALICE), artGobblers.gooBalance(N_ALICE));
        assertEq(artGobblers.getUserEmissionMultiple(ALICE), artGobblers.getUserEmissionMultiple(N_ALICE));
    }

    function testThreeStakersParityNoGooInjection() public {
        uint256[] memory aGobblers = new uint256[](1);
        aGobblers[0] = 1;
        uint256[] memory bGobblers = new uint256[](1);
        bGobblers[0] = 2;
        uint256[] memory cGobblers = new uint256[](1);
        cGobblers[0] = 3;

        assertEq(artGobblers.gooBalance(ALICE), artGobblers.gooBalance(N_ALICE));
        assertEq(artGobblers.getUserEmissionMultiple(ALICE), artGobblers.getUserEmissionMultiple(N_ALICE));
        assertEq(artGobblers.gooBalance(BOB), artGobblers.gooBalance(N_BOB));
        assertEq(artGobblers.getUserEmissionMultiple(BOB), artGobblers.getUserEmissionMultiple(N_BOB));
        assertEq(artGobblers.gooBalance(CHAD), artGobblers.gooBalance(N_CHAD));
        assertEq(artGobblers.getUserEmissionMultiple(CHAD), artGobblers.getUserEmissionMultiple(N_CHAD));

        console.log("\nStarting Goo balances:");
        console.log(artGobblers.gooBalance(ALICE));
        console.log(artGobblers.gooBalance(BOB));
        console.log(artGobblers.gooBalance(CHAD));

        burnGoo(ALICE);
        burnGoo(N_ALICE);
        burnGoo(BOB);
        burnGoo(N_BOB);
        burnGoo(CHAD);
        burnGoo(N_CHAD);

        depositEverything(ALICE, aGobblers);
        depositEverything(BOB, bGobblers);
        depositEverything(CHAD, cGobblers);

        // >> 1 year
        console.log("FF 1 Year");
        vm.warp(block.timestamp + (1 * 365 days));

        console.log("\nGobbler Goo balances:");
        console.log(gooFarm.gooEarnedByGobbler(1));
        console.log(gooFarm.gooEarnedByGobbler(2));
        console.log(gooFarm.gooEarnedByGobbler(3));

        console.log("\nxGoo balances:");
        console.log(gooFarm.balanceOf(ALICE));
        console.log(gooFarm.balanceOf(BOB));
        console.log(gooFarm.balanceOf(CHAD));

        console.log("\nwithdraws:");
        console.log("Farm\t", artGobblers.gooBalance(address(gooFarm)));
        console.log("ALICE\t", getGobblersGooInFarm(aGobblers) + getTotalGooBalance(ALICE));
        withdrawEverything(ALICE, aGobblers);

        console.log("Farm\t", artGobblers.gooBalance(address(gooFarm)));
        console.log("BOB\t", getGobblersGooInFarm(bGobblers) + getTotalGooBalance(BOB));
        withdrawEverything(BOB, bGobblers);

        console.log("Farm\t", artGobblers.gooBalance(address(gooFarm)));
        console.log("CHAD\t", getGobblersGooInFarm(cGobblers) + getTotalGooBalance(CHAD));
        withdrawEverything(CHAD, cGobblers);

        console.log("\nfinal balances:");
        console.log("ALICE\t", getTotalGooBalance(ALICE));
        console.log("N_ALI\t", getTotalGooBalance(N_ALICE));
        console.log("BOB\t", getTotalGooBalance(BOB));
        console.log("N_BOB\t", getTotalGooBalance(N_BOB));
        console.log("CHAD\t", getTotalGooBalance(CHAD));
        console.log("N_CH\t", getTotalGooBalance(N_CHAD));
        console.log("Farm\t", getTotalGooBalance(address(gooFarm)));

        assertEq(artGobblers.gooBalance(ALICE), artGobblers.gooBalance(N_ALICE));
        assertEq(artGobblers.getUserEmissionMultiple(ALICE), artGobblers.getUserEmissionMultiple(N_ALICE));
        assertEq(artGobblers.gooBalance(BOB), artGobblers.gooBalance(N_BOB));
        assertEq(artGobblers.getUserEmissionMultiple(BOB), artGobblers.getUserEmissionMultiple(N_BOB));
        assertEq(artGobblers.gooBalance(CHAD), artGobblers.gooBalance(N_CHAD));
        assertEq(artGobblers.getUserEmissionMultiple(CHAD), artGobblers.getUserEmissionMultiple(N_CHAD));
    }

    function testThreeStakersOutperformWithGooInjection() public {
        uint256[] memory aGobblers = new uint256[](1);
        aGobblers[0] = 1;
        uint256[] memory bGobblers = new uint256[](1);
        bGobblers[0] = 2;
        uint256[] memory cGobblers = new uint256[](1);
        cGobblers[0] = 3;

        // TODO Airdrop set to 0, math fixes needed
        uint256 airdropAmount = 0e18;

        assertEq(artGobblers.gooBalance(ALICE), artGobblers.gooBalance(N_ALICE));
        assertEq(artGobblers.getUserEmissionMultiple(ALICE), artGobblers.getUserEmissionMultiple(N_ALICE));
        assertEq(artGobblers.gooBalance(BOB), artGobblers.gooBalance(N_BOB));
        assertEq(artGobblers.getUserEmissionMultiple(BOB), artGobblers.getUserEmissionMultiple(N_BOB));
        assertEq(artGobblers.gooBalance(CHAD), artGobblers.gooBalance(N_CHAD));
        assertEq(artGobblers.getUserEmissionMultiple(CHAD), artGobblers.getUserEmissionMultiple(N_CHAD));

        console.log("\nStarting Goo balances:");
        console.log(artGobblers.gooBalance(ALICE));
        console.log(artGobblers.gooBalance(BOB));
        console.log(artGobblers.gooBalance(CHAD));

        increaseAllUsersGooEqually(airdropAmount);
        console.log("airdropping\n", airdropAmount);

        depositEverything(ALICE, aGobblers);
        depositEverything(BOB, bGobblers);
        depositEverything(CHAD, cGobblers);

        vm.warp(block.timestamp + 1);
        gooFarm._updateBalances();

        // >> 1 year
        console.log("\nFF 1 Year");
        vm.warp(block.timestamp + (1000 * 365 days));

        console.log("\nGobbler Goo balances:");
        console.log(gooFarm.gooEarnedByGobbler(1));
        console.log(gooFarm.gooEarnedByGobbler(2));
        console.log(gooFarm.gooEarnedByGobbler(3));

        console.log("\nxGoo balances:");
        console.log(gooFarm.balanceOf(ALICE));
        console.log(gooFarm.balanceOf(BOB));
        console.log(gooFarm.balanceOf(CHAD));

        console.log("\nGoo earned by xGoo:");
        gooFarm._updateBalances();
        console.log("Farm bal:");
        console.log(gooFarm.lastFarmGooBalance());
        console.log("xGoo bal:");
        console.log(gooFarm.lastFarmGooBalance() - gooFarm.lastGobblersGooBalance());

        console.log("\nwithdraws:");
        console.log("Farm\t", artGobblers.gooBalance(address(gooFarm)));
        console.log("ALICE\t", getGobblersGooInFarm(aGobblers) + getTotalGooBalance(ALICE));
        withdrawEverything(ALICE, aGobblers);

        console.log("Farm\t", artGobblers.gooBalance(address(gooFarm)));
        console.log("BOB\t", getGobblersGooInFarm(bGobblers) + getTotalGooBalance(BOB));
        withdrawEverything(BOB, bGobblers);

        console.log("Farm\t", artGobblers.gooBalance(address(gooFarm)));
        console.log("CHAD\t", getGobblersGooInFarm(cGobblers) + getTotalGooBalance(CHAD));
        withdrawEverything(CHAD, cGobblers);

        console.log("\nfinal balances:");
        console.log("ALICE\t", getTotalGooBalance(ALICE));
        console.log("N_ALI\t", getTotalGooBalance(N_ALICE));
        console.log("BOB\t", getTotalGooBalance(BOB));
        console.log("N_BOB\t", getTotalGooBalance(N_BOB));
        console.log("CHAD\t", getTotalGooBalance(CHAD));
        console.log("N_CH\t", getTotalGooBalance(N_CHAD));
        console.log("Farm\t", artGobblers.gooBalance(address(gooFarm)));

        assertGt(artGobblers.gooBalance(ALICE), artGobblers.gooBalance(N_ALICE));
        assertEq(artGobblers.getUserEmissionMultiple(ALICE), artGobblers.getUserEmissionMultiple(N_ALICE));
        assertGt(artGobblers.gooBalance(BOB), artGobblers.gooBalance(N_BOB));
        assertEq(artGobblers.getUserEmissionMultiple(BOB), artGobblers.getUserEmissionMultiple(N_BOB));
        assertGt(artGobblers.gooBalance(CHAD), artGobblers.gooBalance(N_CHAD));
        assertEq(artGobblers.getUserEmissionMultiple(CHAD), artGobblers.getUserEmissionMultiple(N_CHAD));
    }

    /*//////////////////////////////////////////////////////////////
                                TEST UTILS
    //////////////////////////////////////////////////////////////*/

    function logBalances(address user, string memory name) public view {
        console.log(name, ":");
        console.log("Goo balance\t", getTotalGooBalance(user));
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
        if (artGobblers.gooBalance(user) > 0) gooFarm.deposit(artGobblers.gooBalance(user), user, false);
        vm.stopPrank();
    }

    // Withdraws all a users gobblers and goo from the farm
    function withdrawEverything(address user, uint256[] memory gobblerIDs) internal {
        vm.startPrank(user);
        gooFarm.withdrawGobblers({to: user, gobblerIDs: gobblerIDs});
        gooFarm.withdraw(gooFarm.maxWithdraw(user), user, user);
        vm.stopPrank();
    }

    function increaseAllUsersGooEqually(uint256 amount) internal {
        address[] memory allUsers = new address[](6);
        allUsers[0] = ALICE;
        allUsers[1] = BOB;
        allUsers[2] = CHAD;
        allUsers[3] = N_ALICE;
        allUsers[4] = N_BOB;
        allUsers[5] = N_CHAD;

        for (uint256 i; i < allUsers.length; ++i) {
            deal(address(goo), allUsers[i], amount);
            vm.startPrank(allUsers[i]);
            artGobblers.addGoo(goo.balanceOf(allUsers[i]));
            vm.stopPrank();
        }
    }

    function burnGoo(address user) internal {
        vm.startPrank(user);
        artGobblers.removeGoo(artGobblers.gooBalance(user));
        if (goo.balanceOf(user) > 0) goo.transfer(address(0), goo.balanceOf(user));
        vm.stopPrank();
    }
}
