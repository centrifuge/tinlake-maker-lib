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
        mgr = new TinlakeManager(dai_,
                                 daiJoin_,
                                 drop_, // DROP token
                                 seniorOperator_, // senior operator
                                 address(this),
                                 address(this), // senior tranche
                                 seniorTranche_,
                                 end_,
                                 ilk);
        mgr_ = address(mgr);

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

    function testDeploy() public {

    }
}
