pragma solidity 0.5.12;

import "dss-interfaces/dss/VatAbstract.sol";
import "dss-interfaces/dapp/DSPauseAbstract.sol";
import "dss-interfaces/dss/JugAbstract.sol";
import "dss-interfaces/dss/SpotAbstract.sol";
import "dss-interfaces/dss/GemJoinAbstract.sol";
import "dss-interfaces/dapp/DSTokenAbstract.sol";
import "dss-interfaces/dss/ChainlogAbstract.sol";

interface RwaLiquidationLike {
    function wards(address) external returns (uint256);
    function ilks(bytes32) external returns (bytes32,address,uint48,uint48);
    function rely(address) external;
    function deny(address) external;
    function init(bytes32, uint256, string calldata, uint48) external;
    function tell(bytes32) external;
    function cure(bytes32) external;
    function cull(bytes32) external;
    function good(bytes32) external view;
}

interface RwaOutputConduitLike {
    function wards(address) external returns (uint256);
    function can(address) external returns (uint256);
    function rely(address) external;
    function deny(address) external;
    function hope(address) external;
    function nope(address) external;
    function bud(address) external returns (uint256);
    function kiss(address) external;
    function diss(address) external;
    function pick(address) external;
    function push() external;
}

interface RwaUrnLike {
    function hope(address) external;
}

contract SpellAction {
    // KOVAN ADDRESSES
    // The contracts in this list should correspond to MCD core contracts, verify
    // against the current release list at:
    //     https://changelog.makerdao.com/releases/kovan/latest/contracts.json
    ChainlogAbstract constant CHANGELOG =
        ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address constant NS2DRP_OPERATOR           = 0x27EfE12d1bede473960859E85375FaB75F4C9ffa;
    address constant NS2DRP_GEM                = 0x46b25B14C572670F01De2453B03e001BAcAFF438;
    address constant MCD_JOIN_NS2DRP_A         = 0x56Bc1E875cD1e557B90441ce7402CA2cB88D3819;
    address constant NS2DRP_A_URN              = 0xB1d6C9079CD81e96e1719f1c22F5Fa4285f4e031;
    address constant NS2DRP_A_INPUT_CONDUIT    = 0x27EfE12d1bede473960859E85375FaB75F4C9ffa;
    address constant NS2DRP_A_OUTPUT_CONDUIT   = 0x27EfE12d1bede473960859E85375FaB75F4C9ffa;
    address constant MIP21_LIQUIDATION_ORACLE  = 0xbB24f0c5e50EEA2f19CE996F4dcA6Ce216b58114;

    uint256 constant NS2DRP_THREEPOINTSIX_PERCENT_RATE = 1000000001121484774769253326;


    // precision
    uint256 constant public THOUSAND = 10 ** 3;
    uint256 constant public MILLION  = 10 ** 6;
    uint256 constant public WAD      = 10 ** 18;
    uint256 constant public RAY      = 10 ** 27;
    uint256 constant public RAD      = 10 ** 45;

    uint256 constant NS2DRP_A_INITIAL_DC    = 5 * MILLION * RAD; 
    uint256 constant NS2DRP_A_INITIAL_PRICE = 1060 * WAD; // value ???

    // MIP13c3-SP4 Declaration of Intent & Commercial Points -
    // Off-Chain Asset Backed Lender to onboard Real World Assets
    // as Collateral for a DAI loan
    //
    // https://ipfs.io/ipfs/QmdmAUTU3sd9VkdfTZNQM6krc9jsKgF2pz7W1qvvfJo1xk
    string constant DOC = "QmdmAUTU3sd9VkdfTZNQM6krc9jsKgF2pz7W1qvvfJo1xk";

    function execute() external {
        address MCD_VAT  = ChainlogAbstract(CHANGELOG).getAddress("MCD_VAT");
        address MCD_JUG  = ChainlogAbstract(CHANGELOG).getAddress("MCD_JUG");
        address MCD_SPOT = ChainlogAbstract(CHANGELOG).getAddress("MCD_SPOT");

        // NS2DRP-A collateral deploy

        // Set ilk bytes32 variable
        bytes32 ilk = "NS2DRP-A";

        // add RWA-001 contract to the changelog
        CHANGELOG.setAddress("NS2DRP", NS2DRP_GEM);
        CHANGELOG.setAddress("MCD_JOIN_NS2DRP_A", MCD_JOIN_NS2DRP_A);
        CHANGELOG.setAddress("MIP21_LIQUIDATION_ORACLE", MIP21_LIQUIDATION_ORACLE);
        CHANGELOG.setAddress("NS2DRP_A_URN", NS2DRP_A_URN);
        CHANGELOG.setAddress("NS2DRP_A_INPUT_CONDUIT", NS2DRP_A_INPUT_CONDUIT);
        CHANGELOG.setAddress("NS2DRP_A_OUTPUT_CONDUIT", NS2DRP_A_OUTPUT_CONDUIT);


        // Sanity checks
        require(GemJoinAbstract(MCD_JOIN_NS2DRP_A).vat() == MCD_VAT, "join-vat-not-match");
        require(GemJoinAbstract(MCD_JOIN_NS2DRP_A).ilk() == ilk, "join-ilk-not-match");
        require(GemJoinAbstract(MCD_JOIN_NS2DRP_A).gem() == NS2DRP_GEM, "join-gem-not-match");
        require(GemJoinAbstract(MCD_JOIN_NS2DRP_A).dec() == DSTokenAbstract(NS2DRP_GEM).decimals(), "join-dec-not-match");

        // init the RwaLiquidationOracle
        // doc: "doc"
        // tau: 5 minutes
        RwaLiquidationLike(MIP21_LIQUIDATION_ORACLE).init(
            ilk, NS2DRP_A_INITIAL_PRICE, DOC, 300
        );
        (,address pip,,) = RwaLiquidationLike(MIP21_LIQUIDATION_ORACLE).ilks(ilk);
        CHANGELOG.setAddress("PIP_NS2DRP", pip);

        // Set price feed for NS2DRP
        SpotAbstract(MCD_SPOT).file(ilk, "pip", pip);

        // Init RWA-001 in Vat
        VatAbstract(MCD_VAT).init(ilk);
        // Init RWA-001 in Jug
        JugAbstract(MCD_JUG).init(ilk);

        // Allow RWA-001 Join to modify Vat registry
        VatAbstract(MCD_VAT).rely(MCD_JOIN_NS2DRP_A);

        // Allow RwaLiquidationOracle to modify Vat registry
        VatAbstract(MCD_VAT).rely(MIP21_LIQUIDATION_ORACLE);

        // 5 Million debt ceiling
        VatAbstract(MCD_VAT).file(ilk, "line", NS2DRP_A_INITIAL_DC);
        VatAbstract(MCD_VAT).file("Line", VatAbstract(MCD_VAT).Line() + NS2DRP_A_INITIAL_DC);

        // No dust
        // VatAbstract(MCD_VAT).file(ilk, "dust", 0)

        // 3.6% stability fee
        JugAbstract(MCD_JUG).file(ilk, "duty", NS2DRP_THREEPOINTSIX_PERCENT_RATE);

        // Set the NS2DRP-A min collateralization ratio (e.g. 105% => X = 105)
        SpotAbstract(MCD_SPOT).file(ilk, "mat", 105 * RAY / 100);

        // poke the spotter to pull in a price
        SpotAbstract(MCD_SPOT).poke(ilk);

        // give the urn permissions on the join adapter
        GemJoinAbstract(MCD_JOIN_NS2DRP_A).rely(NS2DRP_A_URN);

        // set up the urn
        RwaUrnLike(NS2DRP_A_URN).hope(NS2DRP_OPERATOR);
    }
}

contract RwaSpell {

    ChainlogAbstract constant CHANGELOG =
        ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    DSPauseAbstract public pause =
        DSPauseAbstract(CHANGELOG.getAddress("MCD_PAUSE"));
    address         public action;
    bytes32         public tag;
    uint256         public eta;
    bytes           public sig;
    uint256         public expiration;
    bool            public done;

    string constant public description = "New Silver Spell Deploy";

    constructor() public {
        sig = abi.encodeWithSignature("execute()");
        action = address(new SpellAction());
        bytes32 _tag;
        address _action = action;
        assembly { _tag := extcodehash(_action) }
        tag = _tag;
        expiration = block.timestamp + 30 days;
    }

    function schedule() public {
        require(block.timestamp <= expiration, "This contract has expired");
        require(eta == 0, "This spell has already been scheduled");
        eta = block.timestamp + DSPauseAbstract(pause).delay();
        pause.plot(action, tag, sig, eta);
    }

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        pause.exec(action, tag, sig, eta);
    }
}