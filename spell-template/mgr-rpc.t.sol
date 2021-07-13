pragma solidity 0.5.12;

import {DssSpellTestBase} from "./spell-rpc.t.sol";
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

interface FileLike {
    function file(bytes32 what, address data) external;
}

interface ERC20Like {
    function mint(address, uint256) external;
}

contract KovanRPC is DssSpellTestBase {
    DSTokenAbstract  public drop;
    TinlakeManager dropMgr;

    // Tinlake
    Root constant root = Root(ROOT);
    MemberList constant memberlist = MemberList(MEMBERLIST);
    EpochCoordinatorLike constant coordinator = EpochCoordinatorLike(COORDINATOR);

    address self = address(this);

    function setUp() public {
        super.setUp();
        self = address(this);
        dropMgr = TinlakeManager(address(mgr));
        drop = DSTokenAbstract(address(dropMgr.gem()));

        // welcome to hevm KYC
        hevm.store(address(root), keccak256(abi.encode(address(this), uint(0))), bytes32(uint(1)));

        root.relyContract(address(memberlist), address(this));

        memberlist.updateMember(self, uint(-1));
        memberlist.updateMember(address(dropMgr), uint(-1));

        // set this contract as ward on the mgr
        hevm.store(address(dropMgr), keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));
        assertEq(dropMgr.wards(self), 1);

        // file MIP21 contracts 
        FileLike(address(mgr)).file("liq", LIQ);
        FileLike(address(mgr)).file("urn", URN);

        // give this address 1500 dai and 1000 drop
        hevm.store(address(dai), keccak256(abi.encode(self, uint(2))), bytes32(uint(1500 ether)));
        hevm.store(address(drop), keccak256(abi.encode(self, uint(0))), bytes32(uint(1)));
        ERC20Like(address(drop)).mint(self, 1000 ether);

        assertEq(dropMgr.wards(self), 1);

        assertEq(dai.balanceOf(self), 1500 ether);
        assertEq(drop.balanceOf(self), 1000 ether);

        // approve the managers
        drop.approve(address(dropMgr), uint(-1));
        dai.approve(address(dropMgr), uint(-1));

        emit log_named_address("mgr", MGR);
        emit log_named_address("drop", DROP);
        emit log_named_address("memberlist", MEMBERLIST);
        emit log_named_address("mgr drop", address(dropMgr.gem()));
        // spell is already executed on kovan
        executeSpell();
        lock();
    }

    function lock() public {
        uint rwaToken = 1 ether;
        dropMgr.lock(rwaToken);
    }

    function testJoinAndDraw() public {
        uint preBal = drop.balanceOf(address(dropMgr));
        assertEq(dai.balanceOf(self), 1500 ether);
        assertEq(drop.balanceOf(self), 1000 ether);

        dropMgr.join(400 ether);
        dropMgr.draw(200 ether);
        assertEq(dai.balanceOf(self), 1700 ether);
        assertEq(drop.balanceOf(self), 600 ether);
        assertEq(drop.balanceOf(address(dropMgr)), preBal + 400 ether);
    }

    function testWipeAndExit() public {
        testJoinAndDraw();
        dropMgr.wipe(10 ether);
        dropMgr.exit(10 ether);
        assertEq(dai.balanceOf(self), 1690 ether);
        assertEq(drop.balanceOf(self), 610 ether);
    }

    function cdptab() public view returns (uint) {
        // Calculate DAI cdp debt
        (, uint art) = vat.urns(ilk, address(dropMgr));
        (, uint rate, , ,) = vat.ilks(ilk);
        return art * rate;
    }
}
