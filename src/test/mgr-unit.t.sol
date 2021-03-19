pragma solidity >=0.5.12;


import "../mgr.sol";

import { Mock } from "./mocks/mock.sol";
import { TrancheMock } from "./mocks/tranche.sol";
import { OperatorMock } from "./mocks/operator.sol";
import { VowMock } from "./mocks/vow.sol";
import { EndMock } from "./mocks/end.sol";
import { DaiJoinMock } from "./mocks/daijoin.sol";
import { Dai } from "dss/dai.sol";
import { Vat } from "dss/vat.sol";
import { Jug } from 'dss/jug.sol';
import { Spotter } from "dss/spot.sol";

import { RwaToken } from "rwa-example/RwaToken.sol";
import { RwaUrn } from "rwa-example/RwaUrn.sol";
import { RwaLiquidationOracle } from "rwa-example/RwaLiquidationOracle.sol";
import { DaiJoin } from 'dss/join.sol';
import { AuthGemJoin } from "dss-gem-joins/join-auth.sol";

import "ds-token/token.sol";
import "ds-test/test.sol";
import "ds-math/math.sol";

interface Hevm {
    function warp(uint) external;
    function store(address,bytes32,bytes32) external;
    function load(address,bytes32) external returns (bytes32);
}

contract TinlakeManagerUnitTest is DSTest, DSMath {
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

    function rad(uint wad) internal pure returns (uint) {
        return wad * 10 ** 27;
    }

    // Maker
    DaiJoin daiJoin;
    EndMock end;
    DSToken dai;
    Vat vat;
    DSToken gov;
    RwaToken rwa;
    AuthGemJoin gemJoin;
    RwaUrn urn;
    RwaLiquidationOracle oracle;
    Jug jug;
    Spotter spotter;

    address daiJoin_;
    address gemJoin_;
    address dai_;
    address vow = address(123);
    address end_;
    address urn_;
    bytes32 constant ilk = "DROP"; // New Collateral Type

    // Tinlake
    DSToken drop;
    TrancheMock seniorTranche;
    OperatorMock seniorOperator;
    TinlakeManager mgr;

    address drop_;
    address seniorTranche_;
    address seniorOperator_;
    address mgr_;
    address self;


    // -- testing --
    Hevm constant hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    uint256 rate;
    uint256 ceiling = 400 ether;
    string doc = "Please sign on the dotted line.";

    function setUp() public {
        hevm.warp(604411200);
        self = address(this);

        dai = new DSToken("DAI");
        dai_ = address(dai);

        end = new EndMock();
        end_ = address(end);

        // deploy governance token
        gov = new DSToken('GOV');
        gov.mint(100 ether);

        // deploy rwa token
        rwa = new RwaToken();

        // standard Vat setup
        vat = new Vat();

        jug = new Jug(address(vat));
        jug.file("vow", vow);
        vat.rely(address(jug));

        spotter = new Spotter(address(vat));
        vat.rely(address(spotter));

        daiJoin = new DaiJoin(address(vat), address(dai));
        daiJoin_ = address(daiJoin);
        vat.rely(address(daiJoin));
        dai.setOwner(address(daiJoin));

        vat.init(ilk);
        vat.file("Line", 100 * rad(ceiling));
        vat.file(ilk, "line", rad(ceiling));

        jug.init(ilk);
        // $ bc -l <<< 'scale=27; e( l(1.08)/(60 * 60 * 24 * 365) )'
        uint256 EIGHT_PCT = 1000000002440418608258400030;
        jug.file(ilk, "duty", EIGHT_PCT);

        oracle = new RwaLiquidationOracle(address(vat), vow);
        oracle.init(
            ilk,
            wmul(ceiling, 1.1 ether),
            doc,
            2 weeks);
        vat.rely(address(oracle));
        (,address pip,,) = oracle.ilks(ilk);

        spotter.file(ilk, "mat", RAY);
        spotter.file(ilk, "pip", pip);
        spotter.poke(ilk);

        gemJoin = new AuthGemJoin(address(vat), ilk, address(rwa));
        gemJoin_ = address(gemJoin);
        vat.rely(gemJoin_);


        // Tinlake Stuff
        drop = new DSToken("DROP");
        drop_ = address(drop);
        seniorTranche = new TrancheMock();
        seniorTranche_ = address(seniorTranche);
        seniorOperator = new OperatorMock(dai_);
        seniorOperator_ = address(seniorOperator);
        seniorTranche.depend("token", drop_);

        mgr = new TinlakeManager(dai_,
                                 daiJoin_,
                                 drop_, // DROP token
                                 seniorOperator_, // senior operator
                                 address(this),
                                 address(this), // senior tranche
                                 seniorTranche_,
                                 end_,
                                 address(vat),
                                 vow,
                                 ilk);
        mgr_ = address(mgr);

        urn = new RwaUrn(address(vat), address(jug), address(gemJoin), address(daiJoin), mgr_);
        urn_ = address(urn);
        gemJoin.rely(address(urn));

        // fund mgr with rwa
        rwa.transfer(mgr_, 1 ether);
        assertEq(rwa.balanceOf(mgr_), 1 ether);

        // auth user to operate
        urn.hope(mgr_);
        mgr.file("urn", address(urn));
        mgr.file("rwaToken", address(rwa));
    }

    function cage() public {
        mgr.cage();
        assert(!mgr.live());
        assert(!mgr.glad());
    }

    function lock(uint wad) public {
      uint initialMgrBalance = rwa.balanceOf(mgr_);
      uint initialJoinBalance = rwa.balanceOf(gemJoin_);

      mgr.lock(wad);

      assertEq(rwa.balanceOf(mgr_), sub(initialMgrBalance, wad));
      assertEq(rwa.balanceOf(gemJoin_), add(initialJoinBalance, wad));
    }

    function join(uint wad) public {
        uint mgrBalanceDROP = drop.balanceOf(mgr_);
        uint selfBalanceDROP = drop.balanceOf(self);

        mgr.join(wad);

        // assert collateral transferred
        assertEq(drop.balanceOf(mgr_), add(mgrBalanceDROP, wad));
        assertEq(drop.balanceOf(self), sub(selfBalanceDROP, wad));
    }

    function exit(uint wad) public {
        uint mgrBalanceDROP = drop.balanceOf(mgr_);
        uint selfBalanceDROP = drop.balanceOf(self);

        mgr.exit(wad);

        // assert collateral was transferred correctly from mgr
        assertEq(drop.balanceOf(mgr_), sub(mgrBalanceDROP, wad));
        assertEq(drop.balanceOf(self), add(selfBalanceDROP, wad));
    }

    function draw(uint wad) public {
        uint selfBalanceDAI = dai.balanceOf(self);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.draw(wad);

        // check DAI were minted & transferred correctly
        assertEq(dai.balanceOf(self), add(selfBalanceDAI, wad));
        assertEq(dai.totalSupply(), add(totalSupplyDAI, wad));
    }

    function wipe(uint wad) public {
        uint selfBalanceDAI = dai.balanceOf(self);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.wipe(wad);

        // check DAI were transferred & burned
        assertEq(dai.balanceOf(self), sub(selfBalanceDAI, wad));
       // assertEq(dai.totalSupply(), sub(totalSupplyDAI, wad));
    }

    function migrate() public {
         // deploy new mgr
        TinlakeManager newMgr = new TinlakeManager(dai_,
                                    daiJoin_,
                                    drop_, // DROP token
                                    seniorOperator_, // senior operator
                                    address(this),
                                    address(this), // senior tranche
                                    seniorTranche_,
                                    end_,
                                    address(vat),
                                    vow,
                                    ilk);
        address newMgr_ = address(newMgr);

        mgr.migrate(newMgr_);


        // check allowance set for dai & collateral
        assertEq(dai.allowance(mgr_, newMgr_), uint256(-1));
        assertEq(drop.allowance(mgr_, newMgr_), uint256(-1));
        // assert live is set to false
        assert(!mgr.live());
    }

    function sink() public {

        mgr.sink();

        (, uint256 art) = vat.urns(ilk, address(urn));
        (, uint256 rate, , ,) = vat.ilks(ilk);
        // assert correct DAI amount was written off
        uint tab = mul(rate, art);

        assertEq(mgr.tab(), tab);
        // assert sink called
        assert(!mgr.glad());
    }

    function tell() public {
        // put collateral into cdp
        uint128 wad = 100 ether;
        testJoin(wad);

        mgr.tell();

        // safe flipped to false
        assert(!mgr.safe());

        assertEq(seniorOperator.calls("redeemOrder"), 1);
        assertEq(seniorOperator.values_uint("redeemOrder_wad"), wad);
    }

    function unwind(uint128 redeemedDAI) public {
        // setup mocks
        seniorOperator.setDisburseValues(redeemedDAI, 0, 0, 0);
        (, uint256 art) = vat.urns(ilk, address(urn));
        (, uint256 rate, , ,) = vat.ilks(ilk);
        uint256 cdptab = mul(art, rate);
        uint selfBalanceDAI = dai.balanceOf(self);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.unwind(1);
        uint256 payback = min(redeemedDAI, divup(cdptab, RAY));
         // make sure redeemed DAI were burned
        assertEq(dai.totalSupply(), sub(totalSupplyDAI, payback));
        // make sure remainder was transferred to operator correctly
        if (redeemedDAI > cdptab) {
            uint remainder = add(selfBalanceDAI, sub(redeemedDAI, cdptab));
            assertEq(dai.balanceOf(self), add(selfBalanceDAI, remainder));
        }
    }

    function recover(uint redeemedDAI, uint epochId) public {
        uint totalSupplyDAI = dai.totalSupply();
        uint mgrTab = mgr.tab();
        dai.transferFrom(self, seniorOperator_, dai.balanceOf(self)); // transfer DAI to opeartor for redemption
        uint operatorBalanceInit = dai.balanceOf(seniorOperator_);
        seniorOperator.setDisburseValues(redeemedDAI, 0, 0, 0);
        
        mgr.recover(epochId);

        // assert dai were transferred from operator correctly
        assertEq(dai.balanceOf(seniorOperator_), sub(operatorBalanceInit, redeemedDAI));      
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
        assertEq(dai.balanceOf(self), surplus);
        assertEq(dai.totalSupply(), sub(totalSupplyDAI, payBack));
    }

    function testLock() public {
      lock(1 ether);
    }

    function testFailLockGlobalSettlement() public {
        cage();
        testLock();
    }

    function testJoin(uint128 wad) public {
        drop.mint(wad);
        drop.approve(mgr_, wad);
        join(wad);
    }

    function testFailJoinGlobalSettlement(uint128 art, uint128 ink, uint128 wad) public {
        cage();
        testJoin(wad);
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

    function testDraw(uint wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        testLock();
        draw(wad);
    }

    function testFailDrawAboveCeiling(uint wad) public {
        assert(ceiling < wad);
        testLock();
        draw(wad);
    }

    function testFailDrawGlobalSettlement() public {
        testLock();
        cage();
        draw(add(ceiling, 1));
    }

    function testExit(uint128 wad) public {
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

    function testFailExitGlobalSettlement(uint128 wad) public {
        // set live to false
        cage();
        testExit(wad);
    }

    function testWipe(uint128 wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        testDraw(wad);
        dai.approve(mgr_, wad);
        wipe(wad);
    }

    function testFailWipeGlobalSettlement(uint128 wad) public {
        // set live to false
        cage();
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

    function testTell() public {
        tell();
    }

    function testFailTellNotSafe() public {
        tell();
        mgr.tell();
    }

    function testSink(uint128 wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        // set safe to false, call tell
        testDraw(wad);
        tell();
        sink();
    }

    function testFailSinkGlobalSettlement() public {
        uint wad = 100 ether;
        testDraw(wad);
        tell();
        cage();
        sink();
    }

    function testFailSinkIsSafe(uint wad) public {
        uint wad = 100 ether;
        // set safe to false, call tell
        testDraw(wad);
        sink();
    }

    function testUnwindFullRepayment(uint128 wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        testDraw(wad);
        dai.transferFrom(self, seniorOperator_, wad);
        // trigger tell condition & set safe to false
        tell();
        unwind(wad);
    }

    function testUnwindPartialRepayment(uint128 wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        testDraw(wad);
        dai.transferFrom(self, seniorOperator_, wad);
        // trigger tell condition & set safe to false
        tell();
        unwind(wad / 2); // Payback half of the loan
    }

    function testFailUnwindGlobalSettlement(uint128 wad) public {
        assert(wad > ceiling); // avoid overflow
        testDraw(wad);
        dai.transferFrom(self, seniorOperator_, wad);
        // trigger tell condition & set safe to false
        tell();
        cage();
        unwind(wad);
    }

    function testFailUnwindInsufficientDAIBalance(uint128 wad) public {
       assert(wad > ceiling); // avoid overflow
        testDraw(wad);
        // trigger tell condition & set safe to false
        tell();
        unwind(wad);
    }

    function testFailUnwindSafe(uint128 wad) public {
        assert(wad > ceiling); // avoid overflow
        testDraw(wad);
        dai.transferFrom(self, seniorOperator_, wad);
        unwind(wad);
    }

    function testMigrate() public {
          migrate();
    }

    function testFullRecover(uint128 wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        testSink(wad);
        recover(wad, 1);
    }

    function testPartialRecover(uint128 wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        if (wad < 2) return; 
        testSink(wad);
        recover(wad/2, 1);
    }

    function testFailRecoverisGlad(uint128 wad) public {
        recover(wad, 1);
    }

    function testRecoverGlobalSettlement(uint128 wad) public {
        if (ceiling < wad) return; // amount has to be below ceiling
        testSink(wad);
        cage();
        recover(wad, 1);
    }
}
