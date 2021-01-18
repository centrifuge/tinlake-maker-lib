pragma solidity >=0.5.12;

import "ds-test/test.sol";
import "../mgr.sol";
 import {Mock} from "../../lib/tinlake/src/test/mock/mock.sol";
import { TrancheMock } from "../../lib/tinlake/src/lender/test/mock/tranche.sol";
import { Operator } from "../../lib/tinlake/src/lender/operator.sol";
import { SimpleToken } from "../../lib/tinlake/src/test/simple/token.sol";
import { Dai } from "dss/dai.sol";
import "dss/vat.sol";
import {DaiJoin} from "dss/join.sol";
import {Spotter} from "dss/spot.sol";

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
    DaiJoin daiJoin;
    Spotter spotter;
    VowMock vow;
    Vat vat;
    Dai dai;
    address dai_;
    address vat_;
    address daiJoin_;
    address vow_;
    bytes32 constant ilk = "DROP"; // New Collateral Type

    // Tinlake
    SimpleToken drop;
    TrancheMock seniorTranche;
    Operator seniorOperator;
    address drop_;
    address seniorTranche_;
    address seniorOperator_;


    TinlakeManager mgr;


    // -- testing --                 
    Hevm constant hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
        mkrDeploy();
        drop = new SimpleToken("DROP", "Tinlake DROP Token");
        drop_ = address(drop);
        seniorTranche = new TrancheMock();
        seniorTranche_ = address(seniorTranche);
        seniorOperator = Operator(seniorTranche_);
        seniorOperator_ = address(seniorOperator);
        seniorTranche.depend("token", drop_);

        mgr = new TinlakeManager(address(vat),
                                     dai_,
                                     daiJoin_,
                                     vow_,
                                     drop_, // DROP token
                                     seniorOperator_, // senior operator
                                     address(this),
                                     seniorTranche_, // senior tranche
                                     ilk);
    }


   // creates all relevant mkr contracts to test the mgr
    function mkrDeploy() public {
        dai = new Dai(0);
        dai_ = address(dai);
        vat = new Vat();
        vat_ = address(vat);
        daiJoin = new DaiJoin(vat_, dai_);
        daiJoin_ = address(daiJoin);
        spotter = new Spotter(vat_);
        vow = new VowMock();
        vow_ = address(vow);
        vat.rely(address(daiJoin));
        spotter = new Spotter(vat_);
        vat.rely(address(spotter));
    }
    function testJoin() public {

    }

   
}
// join
// exit
// draw
// wipe
// setOwner
// migrate
// tell
// unwind
// sink 
// recover
// take
// cage