pragma solidity >=0.5.12;

import "ds-test/test.sol";
import "../mgr.sol";
import "lib/dss-interfaces/src/Interfaces.sol";
import {EpochCoordinator} from "tinlake/lender/coordinator.sol";

interface FlipFabLike {
    function newFlip(address vat, address cat, bytes32 ilk) external returns (address flip);
}
interface ChainlogAbstract {
    function getAddress(bytes32) external returns (address);
}

interface Hevm {
    function warp(uint) external;
    function store(address,bytes32,bytes32) external;
}

interface Root {
    function relyContract(address, address) external;
}

interface MemberList {
    function updateMember(address, uint) external;
}


contract TinlakeManagerTest is DSTest {
    bytes32 constant ilk = "DROP-A"; // New Collateral Type

    TinlakeManager dropMgr;
    Hevm constant hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    VatAbstract vat;
    CatAbstract cat;
    SpotAbstract spotter;
    GemLike constant drop = GemLike(0xE4C72b4dE5b0F9ACcEA880Ad0b1F944F85A9dAA0);
    Root constant root = Root(0x53b2d22d07E069a3b132BfeaaD275b10273d381E);
    MemberList constant memberlist = MemberList(0x5B5CFD6E45F1407ABCb4BFD9947aBea1EA6649dA);
    DaiAbstract dai;
    EpochCoordinator constant coordinator = EpochCoordinator(0xFE860d06fF2a3A485922A6a029DFc1CD8A335288);
    ChainlogAbstract constant CHANGELOG = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    FlipFabLike constant flip_fab = FlipFabLike(0x4ACdbe9dd0d00b36eC2050E805012b8Fc9974f2b);
    
    function setUp() public {
        vat = VatAbstract(CHANGELOG.getAddress("MCD_VAT"));
        cat = CatAbstract(CHANGELOG.getAddress("MCD_CAT"));
        dai = DaiAbstract(CHANGELOG.getAddress("MCD_DAI"));
        spotter = SpotAbstract(CHANGELOG.getAddress("MCD_SPOT"));

        address flip = flip_fab.newFlip(address(vat),
                                        address(cat),
                                        ilk);
        // deploy dropMgr
        dropMgr = new TinlakeManager(address(vat),
                                     CHANGELOG.getAddress("MCD_DAI"),
                                     address(flip),
                                     CHANGELOG.getAddress("MCD_JOIN_DAI"),
                                     CHANGELOG.getAddress("MCD_VOW"),
                                     0xE4C72b4dE5b0F9ACcEA880Ad0b1F944F85A9dAA0, // DROP token
                                     0x230f2E19D6c2Dc0c441c2150D4dD9d67B563A60C, // senior operator
                                     0x961e1d4c9A7C0C3e05F17285f5FA34A66b62dBb1, // TIN token
                                     address(this),
                                     0xdA0bA5Dd06C8BaeC53Fa8ae25Ad4f19088D6375b, // assessor
                                     0xfB30B47c47E2fAB74ca5b0c1561C2909b280c4E5, // senior tranche
                                     bytes32("DROP-A"));

        // welcome to hevm KYC
        hevm.store(address(root), keccak256(abi.encode(address(this), uint(0))), bytes32(uint(1)));
        root.relyContract(address(memberlist), address(this));
        memberlist.updateMember(address(this), uint(-1));

        memberlist.updateMember(address(dropMgr), uint(-1));

        // give this address 500 dai and 100 drop
        hevm.store(address(dai), keccak256(abi.encode(address(this), uint(2))), bytes32(uint(500 ether)));
        hevm.store(address(drop), keccak256(abi.encode(address(this), uint(8))), bytes32(uint(100 ether)));
        assertEq(dai.balanceOf(address(this)), 500 ether);
        assertEq(drop.balanceOf(address(this)), 100 ether);
        drop.approve(address(dropMgr), uint(-1));

    }

    function testSanity() public {
        assertEq(address(dropMgr.vat), address(vat));
    }

    /* function testVariables() public { */
    /*     (,,,uint line,) = vat.ilks(ilk); */
    /*     assertEq(line, uint(10000 * 10 ** 45)); */
    /*     (, uint mat) = spotter.ilks(ilk); */
    /*     assertEq(mat, uint(1500000000 ether)); */
    /*     (uint tax,) = jug.ilks(ilk); */
    /*     assertEq(tax, uint(1.05 * 10 ** 27)); */
    /*     (address flip, uint chop, uint lump) = cat.ilks(ilk); */
    /*     assertEq(flip, address(dropMgr)); */
    /*     assertEq(chop, ONE); */
    /*     assertEq(lump, uint(10000 ether)); */
    /*     assertEq(vat.wards(address(dropMgr)), 1); */
    /* } */

    function testJoinAndDraw() public {
        assertEq(dai.balanceOf(address(this)), 500 ether);
        assertEq(drop.balanceOf(address(this)), 100 ether);
        dropMgr.join(6 ether);
        dropMgr.draw(2 ether, address(this));
        assertEq(dai.balanceOf(address(this)), 502 ether);
        assertEq(drop.balanceOf(address(this)), 76 ether);
    }

    function testWipeAndExit() public {
        testJoinAndDraw();
        dropMgr.wipe(1 ether);
        dropMgr.exit(address(this), 1 ether);
        assertEq(dai.balanceOf(address(this)), 501 ether);
        assertEq(drop.balanceOf(address(this)), 77 ether);
    }

    function testTellAndUnwind() public {
        testJoinAndDraw();
        // we are authorized, so can call tell even if tellCondition is not met.
        dropMgr.tell();
        // all of the drop is in the redeemer now
        assertEq(drop.balanceOf(address(dropMgr)), 0);
        hevm.warp(now + 2 days);
        coordinator.closeEpoch();
        dropMgr.unwind(2);
        assertEq(dai.balanceOf(address(this)), 506 ether);
    }

    /* function testKick() public { */
    /*     testJoinAndDraw(); */
    /*     dropMgr.tell(); */
    /*     dropPip.poke(bytes32(uint(1))); */
    /*     spotter.poke(ilk); */
    /*     cat.bite(ilk, address(dropMgr)); */
    /*     assertEq(vat.gem(ilk, address(dropMgr)), 6 ether); */
    /* } */

    /* function testRecover() public { */
    /*     testKick(); */
    /*     hevm.warp(now + 2 days); */
    /*     coordinator.closeEpoch(); */
    /*     dropMgr.recover(2); */
    /*     // liquidation penalty is 0% */
    /*     assertEq(dai.balanceOf(address(this)), 506 ether); */
    /*     assertEq(dai.balanceOf(address(vow)), 0 ether); */
    /* } */

    /* function testFlip() public { */
    /*     assertEq(address(seniorTranche), address(seniorOperator.tranche())); */
    /*     this.file(address(cat), ilk, "lump", uint(1 ether)); // 1 unit of collateral per batch */
    /*     this.file(address(cat), ilk, "chop", ONE); */
    /*     dropJoin.join(address(this), 1 ether); */
    /*     vat.frob(ilk, address(this), address(this), address(this), 1 ether, 1 ether); // Maximun DAI generated */
    /*     dropPip.poke(bytes32(uint(1))); */
    /*     spotter.poke(ilk); */
    /*     assertEq(vat.gem(ilk, address(dropFlip)), 0); */
    /*     uint batchId = cat.bite(ilk, address(this)); */
    /*     (uint epoch, uint supplyOrd, uint redeemOrd) = seniorTranche.users(address(dropFlip)); */
    /*     assertEq(redeemOrd, 1 ether); */

    /*     hevm.warp(now + 1 days); */
    /*     coordinator.closeEpoch(); */

    /*     assertEq(dropFlip.tab(), 1 ether * 10**27); */
    /*     dropFlip.take(); */
    /*     assertEq(dropFlip.tab(), 0); */

    /* } */
}
