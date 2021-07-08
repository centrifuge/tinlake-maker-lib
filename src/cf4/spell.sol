pragma solidity 0.5.12;

import "dss-interfaces/dss/VatAbstract.sol";
import "dss-interfaces/dapp/DSPauseAbstract.sol";
import "dss-interfaces/dss/JugAbstract.sol";
import "dss-interfaces/dss/SpotAbstract.sol";
import "dss-interfaces/dss/GemJoinAbstract.sol";
import "dss-interfaces/dapp/DSTokenAbstract.sol";
import "dss-interfaces/dss/ChainlogAbstract.sol";
import "./cf4-config.sol";

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

contract SpellAction is POOL_CONFIG {
    // KOVAN ADDRESSES
    // The contracts in this list should correspond to MCD core contracts, verify
    // against the current release list at:
    // https://changelog.makerdao.com/releases/kovan/1.9.1/contracts.json
    ChainlogAbstract constant CHANGELOG =
        ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    // MIP13c3-SP4 Declaration of Intent & Commercial Points -
    // Off-Chain Asset Backed Lender to onboard Real World Assets
    // as Collateral for a DAI loan
    // https://ipfs.io/ipfs/QmSwZzhzFgsbduBxR4hqCavDWPjvAHbNiqarj1fbTwpevR
    string constant DOC = "QmSwZzhzFgsbduBxR4hqCavDWPjvAHbNiqarj1fbTwpevR";

    function execute() external {
        address MCD_VAT  = ChainlogAbstract(CHANGELOG).getAddress("MCD_VAT");
        address MCD_JUG  = ChainlogAbstract(CHANGELOG).getAddress("MCD_JUG");
        address MCD_SPOT = ChainlogAbstract(CHANGELOG).getAddress("MCD_SPOT");
        address MIP21_LIQUIDATION_ORACLE = ChainlogAbstract(CHANGELOG).getAddress("MIP21_LIQUIDATION_ORACLE");


        // add addresses to changelog
        CHANGELOG.setAddress(dropID, DROP);
        CHANGELOG.setAddress(joinID, MCD_JOIN);
        CHANGELOG.setAddress(urnID, URN);
        CHANGELOG.setAddress(inputConduitID, INPUT_CONDUIT);
        CHANGELOG.setAddress(outputConduitID, OUTPUT_CONDUIT);


        // Sanity checks
        require(GemJoinAbstract(MCD_JOIN).vat() == MCD_VAT, "join-vat-not-match");
        require(GemJoinAbstract(MCD_JOIN).ilk() == ilk, "join-ilk-not-match");
        require(GemJoinAbstract(MCD_JOIN).gem() == GEM, "join-gem-not-match");
        require(GemJoinAbstract(MCD_JOIN).dec() == DSTokenAbstract(GEM).decimals(), "join-dec-not-match");

        // init the RwaLiquidationOracle
        // doc: "IPFS Hash"
        // tau: 5 minutes
        RwaLiquidationLike(MIP21_LIQUIDATION_ORACLE).init(
            ilk, INITIAL_PRICE, DOC, 300
        );
        (,address pip,,) = RwaLiquidationLike(MIP21_LIQUIDATION_ORACLE).ilks(ilk);
        CHANGELOG.setAddress(pipID, pip);

        // Set price feed for CF4DRP
        SpotAbstract(MCD_SPOT).file(ilk, "pip", pip);

        // Init CF4DRP in Vat
        VatAbstract(MCD_VAT).init(ilk);
        // Init CF4DRP in Jug
        JugAbstract(MCD_JUG).init(ilk);

        // Allow CF4DRP Join to modify Vat registry
        VatAbstract(MCD_VAT).rely(MCD_JOIN);

        // 5 Million debt ceiling
        VatAbstract(MCD_VAT).file(ilk, "line", DC);
        VatAbstract(MCD_VAT).file("Line", VatAbstract(MCD_VAT).Line() + DC);

        // No dust
        // VatAbstract(MCD_VAT).file(ilk, "dust", 0)

        // set stability fee
        JugAbstract(MCD_JUG).file(ilk, "duty", RATE);

        // Set the CF4DRP-A min collateralization ratio)
        SpotAbstract(MCD_SPOT).file(ilk, "mat", MAT);

        // poke the spotter to pull in a price
        SpotAbstract(MCD_SPOT).poke(ilk);

        // give the urn permissions on the join adapter
        GemJoinAbstract(MCD_JOIN).rely(URN);

        // set up the urn
        RwaUrnLike(URN).hope(OPERATOR);
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

    string constant public description = "RWA Spell Deploy";

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
