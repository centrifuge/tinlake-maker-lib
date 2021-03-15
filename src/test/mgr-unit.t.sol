pragma solidity >=0.5.12;


import "../mgr.sol";
 import {Mock} from "../../lib/tinlake/src/test/mock/mock.sol";
import { TrancheMock } from "../../lib/tinlake/src/lender/test/mock/tranche.sol";
import { OperatorMock } from "./mocks/tinlake/operator.sol";
import { SimpleToken } from "../../lib/tinlake/src/test/simple/token.sol";
import { VatMock } from "./mocks/vat.sol";
import { VowMock } from "./mocks/vow.sol";
import { EndMock } from "./mocks/end.sol";
import { DaiJoinMock } from "./mocks/daijoin.sol";
import { SpotterMock } from "./mocks/spotter.sol";
import { Dai } from "dss/dai.sol";
import "ds-test/test.sol";

interface Hevm {
    function warp(uint) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external returns (bytes32);
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
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x > y ? y : x;
    }

    // Maker
    DaiJoinMock daiJoin;
    SpotterMock spotter;
    VowMock vow;
    VatMock vat;
    EndMock end;
    Dai dai;
    address dai_;
    address vat_;
    address daiJoin_;
    address vow_;
    address end_;
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
    uint rate;

    function setUp() public {
        mkrDeploy();
        drop = new SimpleToken("DROP", "Tinlake DROP Token");
        drop_ = address(drop);
        seniorTranche = new TrancheMock();
        seniorTranche_ = address(seniorTranche);
        seniorOperator = new OperatorMock(dai_);
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
                                     end_,
                                     ilk);
        mgr_ = address(mgr);
        assertEq(vat.calls("hope"), 1);

        // permissions
        vat.rely(mgr_);
        vow.rely(mgr_);
    }

   // creates all relevant mkr contracts to test the mgr
    function mkrDeploy() public {
        dai = new Dai(0);
        dai_ = address(dai);
        vat = new VatMock();
        vat_ = address(vat);
        daiJoin = new DaiJoinMock(dai_);
        daiJoin_ = address(daiJoin);
        spotter = new SpotterMock();
        vow = new VowMock();
        vow_ = address(vow);
        end = new EndMock();
        end_ = address(end);
        self = address(this);

        // setup permissions
        dai.rely(daiJoin_);
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
        assert(!mgr.glad());
    }

    function changeOperator() public {
        // change mgr operator to different address
        address random_ = address(new TrancheMock());
        mgr.setOperator(random_);
        assertEq(mgr.operator(), random_);
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

    function draw(uint wad) public {
        uint selfBalanceDAI = dai.balanceOf(self);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.draw(wad);
        // check DAI were minted & transferred correctly
        assertEq(dai.balanceOf(self), add(selfBalanceDAI, wad));
        // assertEq(dai.totalSupply(), sub(totalSupplyDAI, wad));

        // assert frob was called with correct values
        assertEq(vat.calls("frob"), 1);
        assertEq(vat.values_bytes32("frob_i"), mgr.ilk());
        assertEq(vat.values_address("frob_u"), mgr_);
        assertEq(vat.values_address("frob_v"), mgr_);
        assertEq(vat.values_address("frob_w"), mgr_);
        assertEq(vat.values_int("frob_dink"), 0);
        assertEq(vat.values_int("frob_dart"), int(wad));
    }

    function wipe(uint wad) public {
        uint selfBalanceDAI = dai.balanceOf(self);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.wipe(wad);

        // check DAI were transferred & burned
        assertEq(dai.balanceOf(self), sub(selfBalanceDAI, wad));
        // assertEq(dai.totalSupply(), sub(totalSupplyDAI, wad));

        // assert frob was called with correct values
        assertEq(vat.calls("frob"), 2); // 1 call on draw &  1 call on wipe
        assertEq(vat.values_bytes32("frob_i"), mgr.ilk());
        assertEq(vat.values_address("frob_u"), mgr_);
        assertEq(vat.values_address("frob_v"), mgr_);
        assertEq(vat.values_address("frob_w"), mgr_);
        assertEq(vat.values_int("frob_dink"), 0);
        assertEq(vat.values_int("frob_dart"), -int(wad));
    }

    function unwind(uint128 art, uint128 redeemedDAI, uint gem, uint remainingDROP) public {
        // setup mocks
        seniorOperator.setDisburseValues(redeemedDAI, 0, 0, remainingDROP);
        vat.setArt(art);
        vat.setInk(gem);

        uint selfBalanceDAI = dai.balanceOf(self);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.unwind(1);

        uint payback = min(art, redeemedDAI);
        uint returnedDROP = sub(gem, remainingDROP);

         // make sure redeemed DAI were burned
        assertEq(dai.totalSupply(), sub(totalSupplyDAI, payback));

        // assert frob was called with correct values
        assertEq(vat.calls("frob"), 2); // 1 call on tell&join & 1 call on unwind
        assertEq(vat.values_bytes32("frob_i"), mgr.ilk());
        assertEq(vat.values_address("frob_u"), mgr_);
        assertEq(vat.values_address("frob_v"), mgr_);
        assertEq(vat.values_address("frob_w"), mgr_);
        assertEq(vat.values_int("frob_dink"), 0);
        assertEq(vat.values_int("frob_dart"), -int(payback));

        // assert slip was called with correct values
        assertEq(vat.calls("slip"), 2); // 1 call on tell&join & 1 call on unwind
        assertEq(vat.values_address("slip_usr"), mgr_);
        assertEq(vat.values_bytes32("slip_ilk"), mgr.ilk());
        assertEq(vat.values_int("slip_wad"), -int(returnedDROP));

        // make sure remainder was transferred to operator correctly
        if (redeemedDAI > art) {
            uint remainder = selfBalanceDAI + (redeemedDAI - art);
            assertEq(dai.balanceOf(self), add(selfBalanceDAI, remainder));
        }
    }

    function sink(uint art, uint ink) public {
        vat.setInk(ink);
        vat.setArt(art);

        // assert
        mgr.sink();

        // assert grab was called with correct values
        assertEq(vat.calls("grab"), 1);
        assertEq(vat.values_bytes32("grab_i"), mgr.ilk());
        assertEq(vat.values_address("grab_u"), mgr_);
        assertEq(vat.values_address("grab_v"), mgr_);
        assertEq(vat.values_address("grab_w"), vow_);
        assertEq(vat.values_int("grab_dink"), -int(ink));
        assertEq(vat.values_int("grab_dart"), -int(art));

        // assert slip was called with correct values
        assertEq(vat.calls("slip"), 2); // 1 call on join & 1 call on sink
        assertEq(vat.values_address("slip_usr"), mgr_);
        assertEq(vat.values_bytes32("slip_ilk"), mgr.ilk());
        assertEq(vat.values_int("slip_wad"), -int(ink));

        // assert correct DAI amount was written off
        uint tab = mul(vat.values_uint("rate"), art);
        assertEq(mgr.tab(), tab);

        // assert sink called
        assert(!mgr.glad());
    }

    function migrate() public {
         // deploy new mgr
        TinlakeManager newMgr = new TinlakeManager(address(vat),
                                    dai_,
                                    daiJoin_,
                                    vow_,
                                    drop_, // DROP token
                                    seniorOperator_, // senior operator
                                    address(this),
                                    seniorTranche_, // senior tranche
                                    end_,
                                    ilk);
        address newMgr_ = address(newMgr);

        mgr.migrate(newMgr_);

        // assert hope was called
        assertEq(vat.calls("hope"), 3); // 2 x for daijoin inside mgr constructor + 1 x in hope
        // check allowance set for dai & collateral
        assertEq(dai.allowance(mgr_, newMgr_), uint(-1));
        assertEq(drop.allowance(mgr_, newMgr_), uint(-1));
        // assert live is set to false
        assert(!mgr.live());
    }

    function recover(uint redeemedDAI, uint epochId) public {
        // dai balance of mgr operator before take
        uint operatorBalanceDAI = dai.balanceOf(self);
        uint mgrTab = mgr.tab();

        // mint dai that can be disbursed
        dai.mint(seniorOperator_, redeemedDAI); // mint enough DAI for redemptio
        seniorOperator.setDisburseValues(redeemedDAI, 0, 0, 0);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.recover(epochId);

        // assert dai were transferred from operator correctly
        assertEq(dai.balanceOf(seniorOperator_), 0);

        uint payBack = min(redeemedDAI,  mgrTab / ONE);
        uint surplus = 0;
        if (redeemedDAI > payBack) {
            surplus = sub(redeemedDAI, payBack);
        }
        if (end.debt() > 0) {
            surplus = redeemedDAI;
            payBack = 0;
        }

        assertEq(mgr.tab(), sub(mgrTab, mul(payBack, ONE)));
        assertEq(dai.balanceOf(self), add(operatorBalanceDAI, surplus));
        assertEq(dai.totalSupply(), sub(totalSupplyDAI, payBack));
    }

    function testRecover(uint redeemedDAI, uint epochId, uint128 art, uint128 ink) public {
        // set glad to false & generate tab -> call sink
        testSink(art, ink);
        recover(redeemedDAI, epochId);
    }


    function testFailRecoverisGlad(uint redeemedDAI, uint epochId, uint art, uint ink) public {
        recover(redeemedDAI, epochId);
    }

    function testRecoverNotLive(uint redeemedDAI, uint epochId, uint128 art, uint128 ink) public {
        testSink(art, ink);
        // set live to false, call cage
        cage();
        // set glad to false & generate tab -> call sink
        recover(redeemedDAI, epochId);
    }

    function testRecoverSettled(uint redeemedDAI, uint epochId, uint128 art, uint128 ink) public {
        testSink(art, ink);
        // set live to false, call cage
        cage();
        end.setDebt(1);
        // set glad to false & generate tab -> call sink
        recover(redeemedDAI, epochId);
    }


    function testMigrate() public {
          migrate();
    }

    function testFailMigrateNoAuth() public {
        // remove auth for mgr
        mgr.deny(self);
        migrate();
    }

    function testSink(uint128 art, uint128 ink) public {
        // set safe to false, call tell
        tell();
        sink(art, ink);
    }

    function testFailSinkIsSafe(uint art, uint ink) public {
         // make sure values are in valid range
        assert((ink <= 2 ** 128 ) && (art <= 2 ** 128));
        sink(art, ink);
    }

    function testFailSinkNotLive(uint art, uint ink) public {
         // make sure values are in valid range
        assert((ink <= 2 ** 128 ) && (art <= 2 ** 128));
        // set safe to false, call tell
        tell();
        // set live to false, call cage
        cage();
        sink(art, ink);
    }

    function testFailSinkNotGlad(uint art, uint ink) public {
          // make sure values are in valid range
        assert((ink <= 2 ** 128 ) && (art <= 2 ** 128));
        // set safe to false, call tell
        tell();
        sink(art, ink);
        sink(art, ink); // try to sink second time
    }

    function testFailSinkNoVatAuth(uint art, uint ink) public {
        // make sure values are in valid range
        assert((ink <= 2 ** 128 ) && (art <= 2 ** 128));
        // set safe to false, call tell
        tell();
        // revoke auth permissions from vat
        vat.deny(mgr_);
        sink(art, ink);
    }

    function testFailSinkInkOverFlow(uint art, uint ink) public {
        // ink value has to produce overflow
        assert((ink > 2 ** 255 ) && (art <= 2 ** 128));
        // set safe to false, call tell
        tell();
        sink(art, ink);
    }

    function testFailSinkArtOverFlow(uint art, uint ink) public {
        // art value has to produce overflow
        assert((ink <= 2 ** 128 ) && (art > 2 ** 255));
        // set safe to false, call tell
        tell();
        sink(art, ink);
    }

    function testUnwind(uint128 art, uint128 redeemedDAI, uint128 gem, uint128 remainingDROP) public {
        if (remainingDROP > gem) return; // avoid overflow
        dai.mint(seniorOperator_, redeemedDAI); // mint enough DAI for redemption
        // trigger tell condition & set safe to false
        tell();
        unwind(art, redeemedDAI, gem, remainingDROP);
    }

    function testUnwindFullRepayment(uint128 redeemedDAI, uint128 gem) public {
        uint128 art = redeemedDAI;
        testUnwind(art, redeemedDAI, gem, 0);
    }

    function testUnwindFullRepaymentWithRemainder(uint128 redeemedDAI, uint128 gem, uint128 art) public {
        // make sure art is smaller then redeemedDAI
        if (art >= redeemedDAI ) return;
        testUnwind(art, redeemedDAI, gem, 0);
    }

    function testUnwindPartialRepayment(uint128 redeemedDAI, uint128 gem, uint128 art) public {
         if (art <= redeemedDAI ) return; // make sure art is bigger then redeemedDAI
        testUnwind(art, redeemedDAI, gem, 0);
    }

    function testFailUnwindDropReturnedOverflow(uint128 redeemedDAI, uint128 gem, uint128 art, uint128 remainingDROP) public {
        assert(remainingDROP > gem); // remainingDROP > gem -> gem - remainingDROP will cause overflow
        dai.mint(seniorOperator_, redeemedDAI); // mint enough DAI for redemption
        // trigger tell condition & set safe to false
        tell();
        unwind(art, redeemedDAI, gem, remainingDROP);
    }

    function testFailUnwindNotLive(uint128 art, uint128 redeemedDAI, uint128 gem, uint128 remainingDROP) public {
        assert(remainingDROP > gem); // avoid overflow
        dai.mint(seniorOperator_, redeemedDAI); // mint enough DAI for redemption
        // trigger tell condition & set safe to false
        tell();
        // set live to false
        cage();
        unwind(art, redeemedDAI, gem, remainingDROP);
    }

    function testFailUnwindInsufficientDAIBalance(uint128 art, uint128 redeemedDAI, uint128 gem, uint128 remainingDROP) public {
        assert(remainingDROP > gem && redeemedDAI > 0 ); // make sure test is not failing bc of overflow
        // trigger tell condition & set safe to false
        tell();
        unwind(art, redeemedDAI, gem, remainingDROP);
    }

    function testFailUnwindSafe(uint128 art, uint128 redeemedDAI, uint128 gem, uint128 remainingDROP) public {
        assert(remainingDROP > gem); // avoid overflow
        dai.mint(seniorOperator_, redeemedDAI); // mint enough DAI for redemption
        unwind(art, redeemedDAI, gem, remainingDROP);
    }

    function testWipe(uint128 wad) public {
        testDraw(wad);
        dai.approve(mgr_, wad);
        wipe(wad);
    }

    function testFailWipeNotLive(uint128 wad) public {
        // set live to false
        cage();
        testWipe(wad);
    }

    function testFailWipeNotSafe(uint128 wad) public {
        // set safe to false
        tell();
        testWipe(wad);

    }

    function testFailWipeInsufficientDAIBalance(uint128 wad) public {
       assert(wad > 0);
        testDraw(wad - 1);
        dai.approve(mgr_, wad);
        wipe(wad);
    }

    function testFailWipeNoDAIApproval(uint128 wad) public {
        assert(wad > 0);
        testDraw(wad);
        wipe(wad);
    }

    function testFailWipeOverflow(uint wad) public {
        dai.mint(self, uint(-1)); // mint enough funds for the account
        assert(wad >= 2 ** 255); // wad value has to cause overflow
        dai.approve(mgr_, wad);
        draw(wad);
    }

    function testDraw(uint128 wad) public {
        draw(wad);
    }

    function testFailUnwindNotGlad(uint128 art, uint128 redeemedDAI, uint128 gem, uint128 remainingDROP) public {
        // make sure art is smaller then redeemedDAI
        assert(art >= redeemedDAI );
        // set glad to false, call sink
        mgr.sink();
        assert(!mgr.glad());
        testUnwind(art, redeemedDAI, gem, remainingDROP);
    }

    function testFailDrawNotLive(uint128 wad) public {
         // set live to false
        cage();
        testDraw(wad);
    }

    function testFailDrawNotSafe(uint128 wad) public {
         // set safe to false
        tell();
        testDraw(wad);
    }

    function testFailDrawOverflow(uint wad) public {
        assert(wad >= 2 ** 255); // wad value has to cause overflow
        draw(wad);
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
        // set safe to false
        tell();
        testExit(wad);
    }

    function testFailExitOverflow(uint128 wad) public {
        // join collateral
        testJoin(wad);
        // produce overflow
        exit(uint(-1));
    }

    function testCage(uint128 art, uint128 ink) public {
        testSink(art, ink);
        cage();
    }

    function testCageVatNotLive(uint128 art, uint128 ink) public {
        vat.setLive(0);
        testCage(art, ink);
    }

    function testFailCageNoAuth(uint128 art, uint128 ink) public {
        // revoke access permissions from self
        mgr.deny(self);
        testCage(art, ink);
    }

    function testFailCageGlad() public {
        // revoke access permissions from self
        cage();
    }

    function testChangeOperator() public {
        assertEq(mgr.operator(), self);
        changeOperator();
    }

    function testFailChangeOperatorNotOperator() public {
        assertEq(mgr.operator(), self);
        changeOperator();
        // self not operator of mgr anymore, try changing operator one more time
        changeOperator();
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
        //  vat.rely(mgr_);
        // approve mgr to take collateral
        drop.approve(mgr_, wad);
        join(wad);
    }

    function testFailJoinNotLive(uint128 art, uint128 ink, uint128 wad) public {
        testCage(art, ink);
        testJoin(wad);
    }

    function testFailJoinNotSafe(uint128 wad) public {
         testTell();
         testJoin(wad);
    }

    function testFailJoinOverflow() public {
        uint wad = uint(-1);
        // mint collateral for test contract
        drop.mint(self, wad);
        // approve mgr to take collateral
        drop.approve(mgr_, wad);
        join(wad);
    }

    function testFailJoinCollateralAmountTooHigh(uint128 wad) public {
        // wad = 100 ether;
        // mint collateral for test contract
        uint collateralBalance = sub(wad, 1);
        drop.mint(self, collateralBalance);
        // approve mgr to take collateral
        drop.approve(mgr_, collateralBalance);
        join(wad);
    }

    function testFailJoinNoApproval(uint128 wad) public {
        // for 0 not approval is required
        assert(wad > 0);
        // wad = 100 ether;
        // mint collateral for test contract
        drop.mint(self, wad);
        join(wad);
    }

    function testFailJoinNoVatAuth(uint128 wad) public {
        // wad = 100 ether;
        // mint collateral for test contract
        drop.mint(self, wad);
        // approve mgr to take collateral
        drop.approve(mgr_, wad);
        // revoke mgr auth from vat
        vat.deny(mgr_);
        join(wad);
    }
}
