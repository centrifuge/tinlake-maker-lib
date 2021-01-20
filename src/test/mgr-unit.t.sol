pragma solidity >=0.5.12;

import "ds-test/test.sol";
import "../mgr.sol";
 import {Mock} from "../../lib/tinlake/src/test/mock/mock.sol";
import { TrancheMock } from "../../lib/tinlake/src/lender/test/mock/tranche.sol";
import { OperatorMock } from "./mocks/tinlake/operator.sol";
import { SimpleToken } from "../../lib/tinlake/src/test/simple/token.sol";
import { VatMock } from "./mocks/vat.sol";
import { Dai } from "dss/dai.sol";

interface Hevm {
    function warp(uint) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external returns (bytes32);
}

contract VowMock is Mock {
    function fess(uint256 tab) public {
        values_uint["fess_tab"] = tab;
    }
}

contract TinlakeManagerUnitTest is DSTest {
    uint constant ONE = 10 ** 27;

    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function divup(uint x, uint y) internal pure returns (uint z) {
        z = add(x, sub(y, 1)) / y;
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // Maker
    VatMock daiJoin;
    VatMock spotter;
    VowMock vow;
    VatMock vat;
    Dai dai;
    address dai_;
    address vat_;
    address daiJoin_;
    address vow_;
    bytes32 constant ilk = "DROP"; // New Collateral Type

    // Tinlake
    SimpleToken drop;
    TrancheMock seniorTranche;
    OperatorMock seniorOperator;
    address drop_;
    address seniorTranche_;
    address seniorOperator_;

    TinlakeManager mgr;
    address mgr_;
    address self;

    // -- testing --                 
    Hevm constant hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        mkrDeploy();        
        drop = new SimpleToken("DROP", "Tinlake DROP Token");
        drop_ = address(drop);
        seniorTranche = new TrancheMock();
        seniorTranche_ = address(seniorTranche);
        seniorOperator = new OperatorMock();
        seniorOperator_ = address(seniorOperator);
        seniorTranche.depend("token", drop_);

        // deploy mgr
        mgr = new TinlakeManager(address(vat),
                                     dai_,
                                     daiJoin_,
                                     vow_,
                                     drop_, // DROP token
                                     seniorOperator_, // senior operator
                                     address(this),
                                     seniorTranche_, // senior tranche
                                     ilk);
        mgr_ = address(mgr);
        assertEq(vat.calls("hope"), 1);
    }

   // creates all relevant mkr contracts to test the mgr
    function mkrDeploy() public {
        dai = new Dai(0);
        dai_ = address(dai);
        vat = new VatMock();
        vat_ = address(vat);
        daiJoin = new VatMock(); // TODO
        daiJoin_ = address(daiJoin);
        spotter = new VatMock(); // TODO
        vow = new VowMock();
        vow_ = address(vow);
        self = address(this);

    }

    function join(uint wad) public {
        uint mgrBalanceDROP = drop.balanceOf(mgr_);
        uint selfBalanceDROP = drop.balanceOf(self);

        mgr.join(wad);
        vat.setInk(wad); // helper 

        // assert collateral transferred
        assertEq(drop.balanceOf(mgr_), add(mgrBalanceDROP, wad));
        assertEq(drop.balanceOf(self), sub(selfBalanceDROP, wad));
        
        // assert slip was called with correct values
        assertEq(vat.calls("slip"), 1);
        assertEq(vat.values_address("slip_usr"), mgr_); 
        assertEq(vat.values_bytes32("slip_ilk"), mgr.ilk());
        assertEq(vat.values_int("slip_wad"), int(wad));
        
        // assert frob was called with correct values
        assertEq(vat.calls("frob"), 1);
        assertEq(vat.values_bytes32("frob_i"), mgr.ilk()); 
        assertEq(vat.values_address("frob_u"), mgr_); 
        assertEq(vat.values_address("frob_v"), mgr_); 
        assertEq(vat.values_address("frob_w"), mgr_); 
        assertEq(vat.values_int("frob_dink"), int(wad)); 
        assertEq(vat.values_int("frob_dart"), 0); 
    }

    function tell() public {
        // put collateral into cdp
        uint128 wad = 100 ether;
        testJoin(wad);

        mgr.tell();

        // safe flipped to false
        assert(!mgr.safe());
        // redeemOrder was called with correct values
        assertEq(vat.calls("urns"), 1);
        assertEq(seniorOperator.calls("redeemOrder"), 1);
        assertEq(seniorOperator.values_uint("redeemOrder_wad"), wad);
    }

    function cage() public {
        mgr.cage();
        assert(!mgr.live());
    }

    function  changeOwner() public {
        // change mgr owner to different address
        address random_ = address(new TrancheMock());
        mgr.setOwner(random_);
        assertEq(mgr.owner(), random_);
    }

    function testCageVatNotlive() public {
        // revoke access permissions from self
        mgr.deny(self);
        vat.setLive(0);
        cage();
    }

    function testFailCageNoAuth() public {
        // revoke access permissions from self
        mgr.deny(self);
        cage();
    }

    function testChangeOwner() public {
        assertEq(mgr.owner(), self);
        changeOwner();
    }

    function testFailChangeOwnerNotOwner() public {
        assertEq(mgr.owner(), self);
        changeOwner();
        // self not owner of mgr anymore, try changing owner one more time 
        changeOwner();
    }

    function testTell() public {  
        tell();   
    }

    function testFailTellNotSafe() public {
        tell();
        mgr.tell();
    }

    function testFailTellNotLive() public {
        cage();
        mgr.tell();
    }

    function testFailTellNoAuth() public {
        mgr.deny(self);
        mgr.tell();
    }

    function testJoin(uint128 wad) public {
       // wad = 100 ether;
        // mint collateral for test contract
        drop.mint(self, wad);
        // approve mgr to take collateral
        drop.approve(mgr_, wad);
        // setup vat permissions
        vat.rely(mgr_);
        join(wad);
    }

    function testFailJoinNotLive() public {

    }

    function testFailJoinNotSafe() public {

    }

    function testFailJoinNegativeAmount() public {

    }

    function testFailJoinSenderHasNotEnoughCollateral() public {

    }

    function testFailJoinSenderHasNoCollateralApproval() public {

    }

    function testFailJoinNoVatAuth() public {

    }

    function testSetOwner() public {}
    function testMigrate() public {}
    function testDraw() public {}
    function testWipe() public {}
    function testExit() public {}
    function testUnwind() public {}
    function testSink() public {}
    function testRecover() public {}
    function testTake() public {}
}