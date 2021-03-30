pragma solidity 0.5.12;

import {DssSpellTestBase} from "./spell.t.sol";
import "dss-interfaces/Interfaces.sol";
import {TinlakeManager} from "../mgr.sol";

interface EpochCoordinatorLike {
    function closeEpoch() external;
    function currentEpoch() external returns(uint);
}

interface Hevm {
    function warp(uint) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external returns (bytes32);
}

interface Root {
    function relyContract(address, address) external;
}

interface MemberList {
    function updateMember(address, uint) external;
}

interface AssessorLike {
    function calcSeniorTokenPrice() external returns (uint);
}

contract KovanRPC is DssSpellTestBase {
    DSTokenAbstract  public drop;
    TinlakeManager dropMgr;

    // Tinlake
    Root constant root = Root(0x25dF507570c8285E9c8E7FFabC87db7836850dCd);
    MemberList constant memberlist = MemberList(0xD927F069faf59eD83A1072624Eeb794235bBA652);
    EpochCoordinatorLike constant coordinator = EpochCoordinatorLike(0xB51D3cbaa5CCeEf896B96091E69be48bCbDE8367);
    address constant seniorOperator_ = 0x6B902D49580320779262505e346E3f9B986e99e8;
    address constant seniorTranche_ = 0xDF0c780Ae58cD067ce10E0D7cdB49e92EEe716d9;
    address constant assessor_ = 0x49527a20904aF41d1cbFc0ba77576B9FBd8ec9E5;

    function setUp() public {
        super.setUp();
        dropMgr = TinlakeManager(address(mgr));
        drop = DSTokenAbstract(address(dropMgr.gem()));

        // welcome to hevm KYC
        hevm.store(address(root), keccak256(abi.encode(address(this), uint(0))), bytes32(uint(1)));

        root.relyContract(address(memberlist), address(this));
        memberlist.updateMember(address(this), uint(-1));
        memberlist.updateMember(address(dropMgr), uint(-1));

        // set this contract as owner of dropMgr // override slot 1
        // check what's inside slot 1 with: bytes32 slot = hevm.load(address(dropMgr), bytes32(uint(1)));
        hevm.store(address(dropMgr), bytes32(uint(1)), bytes32(0x0000000000000000000101013bE95e4159a131E56A84657c4ad4D43eC7Cd865d));
        // ste this contract as ward on the mgr
        hevm.store(address(dropMgr), keccak256(abi.encode(address(this), uint(0))), bytes32(uint(1)));

        assertEq(dropMgr.owner(), address(this));
        // give this address 1500 dai and 1000 drop

        hevm.store(address(dai), keccak256(abi.encode(address(this), uint(2))), bytes32(uint(1500 ether)));
        hevm.store(address(drop), keccak256(abi.encode(address(this), uint(8))), bytes32(uint(1000 ether)));
        assertEq(dai.balanceOf(address(this)), 1500 ether);
        assertEq(drop.balanceOf(address(this)), 1000 ether);

        // approve the manager
        drop.approve(address(dropMgr), uint(-1));
        dai.approve(address(dropMgr), uint(-1));


        //execute spell and lock rwa token

        executeSpell();
        lock();
    }

    function lock() public {
        uint rwaToken = 1 ether;
        dropMgr.lock(rwaToken);
    }

    function testJoinAndDraw() public {
        assertEq(dai.balanceOf(address(this)), 1500 ether);
        assertEq(drop.balanceOf(address(this)), 1000 ether);

        dropMgr.join(400 ether);
        dropMgr.draw(200 ether);
        assertEq(dai.balanceOf(address(this)), 1700 ether);
        assertEq(drop.balanceOf(address(this)), 600 ether);
        assertEq(drop.balanceOf(address(dropMgr)), 400 ether);
    }

    function testWipeAndExit() public {
        testJoinAndDraw();
        dropMgr.wipe(10 ether);
        dropMgr.exit(10 ether);
        assertEq(dai.balanceOf(address(this)), 1690 ether);
        assertEq(drop.balanceOf(address(this)), 610 ether);
    }

//    function testAccrueInterest() public {
//        testJoinAndDraw();
//        hevm.warp(now + 2 days);
//        jug.drip(ilk);
//        assertEq(cdptab() / ONE, 200.038762269592882076 ether);
//        dropMgr.wipe(10 ether);
//        dropMgr.exit(10 ether);
//        assertEq(cdptab() / ONE, 190.038762269592882076 ether);
//        assertEq(dai.balanceOf(address(this)), 1690 ether);
//        assertEq(drop.balanceOf(address(this)), 610 ether);
//    }

//    function testTellAndUnwind() public {
//        uint mgrBalanceDrop = 400 ether;
//        uint vaultDebt = 200 ether;
//        testJoinAndDraw();
//        assertEq(drop.balanceOf(address(dropMgr)), mgrBalanceDrop);
//        assertEq(divup(cdptab(), ONE), vaultDebt);
//        uint initialDaiBalance = 1700 ether;
//        assertEq(dai.balanceOf(address(this)), initialDaiBalance);
//        // we are authorized, so can call `tell()`
//        // even if tellCondition is not met.
//        dropMgr.tell();
//        // all of the drop is in the redeemer now
//        assertEq(drop.balanceOf(address(dropMgr)), 0);
//        coordinator.closeEpoch();
//        AssessorLike assessor = AssessorLike(assessor_);
//        uint tokenPrice = assessor.calcSeniorTokenPrice();
//        hevm.warp(now + 2 days);
//        coordinator.currentEpoch();
//
//        vaultDebt = divup(cdptab(), ONE);
//        dropMgr.unwind(coordinator.currentEpoch());
//        // unwinding should unlock the 400 drop in the manager
//        // giving 200 to cover the cdp
//        assertEq(cdptab(), 0 ether); // the cdp should now be debt free
//        // and 200 + interest back to us
//
//        uint redeemedDrop = mul(mgrBalanceDrop, tokenPrice) / ONE;
//        uint expectedValue = sub(add(initialDaiBalance, redeemedDrop), vaultDebt);
//        assert((expectedValue - 1) <= dai.balanceOf(address(this)) && dai.balanceOf(address(this)) <= (expectedValue + 1 ));
//    }
//
//    function testSinkAndRecover() public {
//        testJoinAndDraw();
//        hevm.warp(now + 1 days);
//        jug.drip(ilk);
//        uint preSin = vat.sin(address(vow));
//        (, uint rate, , ,) = vat.ilks(ilk);
//        (uint preink, uint preart) = vat.urns(ilk, address(dropMgr));
//        dropMgr.tell();
//        dropMgr.cull();
//
//        assertEq(vat.gem(ilk, address(dropMgr)), 0);
//        assertEq(preink, 400 ether);
//        // the urn is empty
//        (uint postink, uint postart) = vat.urns(ilk, address(dropMgr));
//        assertEq(postink, 0);
//        assertEq(postart, 0);
//        // and the vow has accumulated sin
//        assertEq(vat.sin(address(vow)) - preSin, preart * rate);
//
//        // try to recover some debt
//        coordinator.closeEpoch();
//        hevm.warp(now + 2 days);
//        dropMgr.recover(coordinator.currentEpoch());
//    }

    function cdptab() public view returns (uint) {
        // Calculate DAI cdp debt
        (, uint art) = vat.urns(ilk, address(dropMgr));
        (, uint rate, , ,) = vat.ilks(ilk);
        return art * rate;
    }
}
