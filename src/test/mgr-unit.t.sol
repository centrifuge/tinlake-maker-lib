pragma solidity >=0.5.12;


import "../mgr.sol";

import { Mock } from "./mocks/mock.sol";
import { TrancheMock } from "./mocks/tranche.sol";
import { OperatorMock } from "./mocks/tinlake/operator.sol";
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
    address daiJoin_;
    EndMock end;
    DSToken dai;
    address dai_;
    Vat vat;
    address vow = address(123);
    address end_;
    bytes32 constant ilk = "DROP"; // New Collateral Type

    // Tinlake
    DSToken drop;
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
    uint256 rate;
    uint256 ceiling = 400 ether;
    string doc = "Please sign on the dotted line.";

    DSToken gov;
    RwaToken rwa;
    AuthGemJoin gemJoin;
    RwaUrn urn;
    RwaLiquidationOracle oracle;

    Jug jug;
    Spotter spotter;


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
        jug.file("vow", address(vow));
        vat.rely(address(jug));

        spotter = new Spotter(address(vat));
        vat.rely(address(spotter));

        daiJoin = new DaiJoin(address(vat), address(dai));
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
        vat.rely(address(gemJoin));


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
                                 ilk);
        mgr_ = address(mgr);

        urn = new RwaUrn(address(vat), address(jug), address(gemJoin), address(daiJoin), mgr_);
        gemJoin.rely(address(urn));

        // fund mgr with rwa
        rwa.transfer(mgr_, 1 ether);

        // auth user to operate
        urn.hope(mgr_);
        mgr.file("urn", address(urn));
        mgr.file("rwaToken", address(rwa));

    }

    function lock() public {
      mgr.lock(1 ether);
      assertEq(rwa.balanceOf(mgr_), 0);
    }

    function join(uint wad) public {
        drop.mint(wad);
        drop.approve(mgr_, wad);

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
        // assertEq(dai.totalSupply(), sub(totalSupplyDAI, wad));
    }

    function wipe(uint wad) public {
        uint selfBalanceDAI = dai.balanceOf(self);
        uint totalSupplyDAI = dai.totalSupply();

        mgr.wipe(wad);

        // check DAI were transferred & burned
        assertEq(dai.balanceOf(self), sub(selfBalanceDAI, wad));
        // assertEq(dai.totalSupply(), sub(totalSupplyDAI, wad));
    }


    function testLock() public {
      lock();
      assertEq(rwa.balanceOf(mgr_), 0);
    }

    function testJoin(uint128 wad) public {
        join(wad);
    }

    function testExit(uint128 wad) public {
        testJoin(wad);
        exit(wad);
    }

    function testDraw() public {
        lock();
        draw(0);
        draw(ceiling);
        draw(0);
    }
    function testFailDrawAboveCeiling() public {
        lock();
        draw(ceiling+1);
    }

}
