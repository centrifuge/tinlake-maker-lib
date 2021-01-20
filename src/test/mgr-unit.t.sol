pragma solidity >=0.5.12;

import "ds-test/test.sol";
import "../mgr.sol";
 import {Mock} from "../../lib/tinlake/src/test/mock/mock.sol";
import { TrancheMock } from "../../lib/tinlake/src/lender/test/mock/tranche.sol";
import { OperatorMock } from "./mocks/tinlake/operator.sol";
import { SimpleToken } from "../../lib/tinlake/src/test/simple/token.sol";
import { VatMock } from "./mocks/vat.sol";
import { DaiJoinMock } from "./mocks/daijoin.sol";
import { SpotterMock } from "./mocks/spotter.sol";
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
    function div(uint256 x, uint256 y) internal pure returns (uint256) {
        require(y > 0, "SafeMath: division by zero");
        uint256 z = x / y;
        return z;
    }

    // Maker
    DaiJoinMock daiJoin;
    SpotterMock spotter;
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
        daiJoin = new DaiJoinMock(); 
        daiJoin_ = address(daiJoin);
        spotter = new SpotterMock();
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

    function exit(uint wad) public {
        uint mgrBalanceDROP = drop.balanceOf(mgr_);
        uint selfBalanceDROP = drop.balanceOf(self);

        mgr.exit(wad);
        vat.setInk(sub(mgrBalanceDROP, wad)); // helper 

        // assert collateral was transferred correctly from mgr
        assertEq(drop.balanceOf(mgr_), sub(mgrBalanceDROP, wad));
        assertEq(drop.balanceOf(self), add(selfBalanceDROP, wad));


         // assert slip was called with correct values
        assertEq(vat.calls("slip"), 2); // 1 call on join + 1 call on exit
        assertEq(vat.values_address("slip_usr"), mgr_); 
        assertEq(vat.values_bytes32("slip_ilk"), mgr.ilk());
        assertEq(vat.values_int("slip_wad"), -int(wad));
        
        // assert frob was called with correct values
        assertEq(vat.calls("frob"), 2); // 1 call on join + 1 call on exit
        assertEq(vat.values_bytes32("frob_i"), mgr.ilk()); 
        assertEq(vat.values_address("frob_u"), mgr_); 
        assertEq(vat.values_address("frob_v"), mgr_); 
        assertEq(vat.values_address("frob_w"), mgr_); 
        assertEq(vat.values_int("frob_dink"), -int(wad)); 
        assertEq(vat.values_int("frob_dart"), 0); 
    }

    function testExit(uint128 wad) public {
        // join collateral
        testJoin(wad);
        exit(wad);
    }

    function testPartialExit(uint128 wad) public {
        testJoin(wad);
        exit(div(wad, 2));
    }

    function testFailExitCollateralAmountTooHigh(uint128 wad) public {
        // join collateral
        testJoin(wad);
        // try to exit more then available
        exit(add(wad, 1));
    }
    
    function testFailExitNotLive(uint128 wad) public {
        // set live to false
        cage();
        testExit(wad);
    }

    function testFailExitNotSafe(uint128 wad) public {
        // set live to false
        tell();
        testExit(wad);
    }

    function testFailExitOverflow(uint128 wad) public {
        // join collateral
        testJoin(wad);
        exit(uint(-1));
    }

    function testCage() public {
        cage();
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
        // set live to false
        cage();
        // revoke access permissions from self
        mgr.deny(self);
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

    function testFailJoinNotLive(uint128 wad) public {
        testCage();
        testJoin(wad);
    }

    function testFailJoinNotSafe(uint128 wad) public {
         testTell();
         testJoin(wad);
    }

    // use uint256 as input to generate an overflow 
    function testFailJoinOverflow() public {
        uint wad = uint(-1);
        // mint collateral for test contract
        drop.mint(self, wad);
        // approve mgr to take collateral
        drop.approve(mgr_, wad);
        // setup vat permissions
        vat.rely(mgr_);
        join(wad);
    }

    function testFailJoinCollateralAmountTooHigh(uint128 wad) public {
        // wad = 100 ether;
        // mint collateral for test contract
        uint collateralBalance = sub(wad, 1);
        drop.mint(self, collateralBalance);
        // approve mgr to take collateral
        drop.approve(mgr_, collateralBalance);
        // setup vat permissions
        vat.rely(mgr_);
        join(wad);
    }

    function testFailJoinNoApproval(uint128 wad) public {
        // for 0 not approval is required
        assert(wad > 0);
        // wad = 100 ether;
        // mint collateral for test contract
        drop.mint(self, wad);
        // setup vat permissions
        vat.rely(mgr_);
        join(wad);
    }

    function testFailJoinNoVatAuth(uint128 wad) public {
        // wad = 100 ether;
        // mint collateral for test contract
        drop.mint(self, wad);
        // approve mgr to take collateral
        drop.approve(mgr_, wad);
        // setup vat permissions
        vat.rely(mgr_);
        // revoke mgr auth from vat
        vat.deny(mgr_);
        join(wad);
    }
}