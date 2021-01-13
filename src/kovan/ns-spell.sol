// Copyright (C) 2020 Maker Ecosystem Growth Holdings, INC.
// 2020 Lucas Vogelsang <lucas@centrifuge.io>,
// 2020 Martin Lundfall <martin.lundfall@gmail.com>
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity >=0.5.12;

import "../../lib/dss-interfaces/src/dapp/DSPauseAbstract.sol";
import "../../lib/dss-interfaces/src/dss/CatAbstract.sol";
import "../../lib/dss-interfaces/src/dss/VowAbstract.sol";
import "../../lib/dss-interfaces/src/dss/FlipperMomAbstract.sol";
import "../../lib/dss-interfaces/src/dss/IlkRegistryAbstract.sol";
import "../../lib/dss-interfaces/src/dss/GemJoinAbstract.sol";
import "../../lib/dss-interfaces/src/dss/JugAbstract.sol";
import "../../lib/dss-interfaces/src/dss/MedianAbstract.sol";
import "../../lib/dss-interfaces/src/dss/OsmAbstract.sol";
import "../../lib/dss-interfaces/src/dss/OsmMomAbstract.sol";
import "../../lib/dss-interfaces/src/dss/SpotAbstract.sol";
import "../../lib/dss-interfaces/src/dss/VatAbstract.sol";

interface ChainlogAbstract {
    function getAddress(bytes32) external returns (address);
    function setAddress(bytes32, address) external;
}

contract NSSpellAction {
    // KOVAN ADDRESSES
    //
    // The contracts in this list should correspond to MCD core contracts, verify
    //  against the current release list at:
    //  https://changelog.makerdao.com/releases/kovan/1.2.2/contracts.json
    ChainlogAbstract constant CHANGELOG = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    address constant NS2DRP            = 0x352Fee834a14800739DC72B219572d18618D9846; // NSDROP 
    address constant MCD_NS2DRP_MGR_A  = 0x65242F75e6cCBF973b15d483dD5F555d13955A1e; // NSDROP MGR
    // address constant MCD_NS2DRP_MGR_A  = 0xEcEDFd8BA8ae39a6Bd346Fe9E5e0aBeA687fFF31; // MGR address to use for test cases to pass
    address constant PIP_NS2DRP        = 0xc7a490C4268f116d5792b3ec1D7e8A1792bb70CA; // unmodified DSValue

    // Decimals & precision
    uint256 constant THOUSAND = 10 ** 3;
    uint256 constant MILLION  = 10 ** 6;
    uint256 constant WAD      = 10 ** 18;
    uint256 constant RAY      = 10 ** 27;
    uint256 constant RAD      = 10 ** 45;

    // Many of the settings that change weekly rely on the rate accumulator
    // described at https://docs.makerdao.com/smart-contract-modules/rates-module
    // To check this yourself, use the following rate calculation (example 8%):
    //
    // $ bc -l <<< 'scale=27; e( l(1.08)/(60 * 60 * 24 * 365) )'
    //
    // A table of rates can be found at
    //    https://ipfs.io/ipfs/QmefQMseb3AiTapiAKKexdKHig8wroKuZbmLtPLv4u2YwW
    uint256 constant NS2DRP_THREEPOINTSIX_PERCENT_RATE = 1000000001121484774769253326;

    function execute() external {
        address MCD_VAT      = CHANGELOG.getAddress("MCD_VAT");
        address MCD_VOW      = CHANGELOG.getAddress("MCD_VOW");
        address MCD_CAT      = CHANGELOG.getAddress("MCD_CAT");
        address MCD_JUG      = CHANGELOG.getAddress("MCD_JUG");
        address MCD_SPOT     = CHANGELOG.getAddress("MCD_SPOT");
        address ILK_REGISTRY = CHANGELOG.getAddress("ILK_REGISTRY");

        // Add NS2DRP contracts to the changelog
        CHANGELOG.setAddress("NS2DRP", NS2DRP);
        CHANGELOG.setAddress("MCD_NS2DRP_MGR_A", MCD_NS2DRP_MGR_A);
        CHANGELOG.setAddress("PIP_NS2DRP", PIP_NS2DRP);

        bytes32 ilk = "NS2DRP-A";

        // Sanity checks
        require(GemJoinAbstract(MCD_NS2DRP_MGR_A).vat() == MCD_VAT, "join-vat-not-match");
        require(GemJoinAbstract(MCD_NS2DRP_MGR_A).ilk() == ilk, "join-ilk-not-match");
        require(GemJoinAbstract(MCD_NS2DRP_MGR_A).gem() == NS2DRP, "join-gem-not-match");
        require(GemJoinAbstract(MCD_NS2DRP_MGR_A).dec() == 18, "join-dec-not-match");

        // Set the DROP PIP in the Spotter
        SpotAbstract(MCD_SPOT).file(ilk, "pip", PIP_NS2DRP);

        // Init NS2DRP-A ilk in Vat & Jug
        VatAbstract(MCD_VAT).init(ilk);
        JugAbstract(MCD_JUG).init(ilk);

        // Allow NS2DRP-A Join to modify Vat registry
        VatAbstract(MCD_VAT).rely(MCD_NS2DRP_MGR_A);
        // Allow NS2DRP-A Join to add Vow debt
        VowAbstract(MCD_VOW).rely(MCD_NS2DRP_MGR_A);

        // Set the global debt ceiling
        VatAbstract(MCD_VAT).file("Line", 1_468_750_000 * RAD);
        // Set the NS2DRP-A debt ceiling
        VatAbstract(MCD_VAT).file(ilk, "line", 5 * MILLION * RAD);
        // Set the NS2DRP-A dust
        VatAbstract(MCD_VAT).file(ilk, "dust", 0);
        // Set the Lot size
        CatAbstract(MCD_CAT).file(ilk, "dunk", 50 * MILLION * RAD);
        // Set the NS2DRP-A no liquidation penalty
        CatAbstract(MCD_CAT).file(ilk, "chop", WAD);
        // Set the NS2DRP-A stability fee (e.g. 1% = 1000000000315522921573372069)
        JugAbstract(MCD_JUG).file(ilk, "duty", NS2DRP_THREEPOINTSIX_PERCENT_RATE);
        // Set the NS2DRP-A min collateralization ratio (e.g. 105% => X = 105)
        SpotAbstract(MCD_SPOT).file(ilk, "mat", 105 * RAY / 100);

        // Update NS2DRP-A spot value in Vat
        SpotAbstract(MCD_SPOT).poke(ilk);
    }
}

contract DssSpell {
    // MCD_PAUSE: "0x8754E6ecb4fe68DaA5132c2886aB39297a5c7189" kovan 1.2.2
    DSPauseAbstract public pause =
        DSPauseAbstract(0x8754E6ecb4fe68DaA5132c2886aB39297a5c7189);
    address         public action;
    bytes32         public tag;
    uint256         public eta;
    bytes           public sig;
    uint256         public expiration;
    bool            public done;

    // Provides a descriptive tag for bot consumption
    string constant public description =
        "2021-01-11 NS-INTEGRATION SPELL";

    constructor() public {
        sig = abi.encodeWithSignature("execute()");
        action = address(new NSSpellAction());
        bytes32 _tag;
        address _action = action;
        assembly { _tag := extcodehash(_action) }
        tag = _tag;
        expiration = now + 30 days;
    }

    function schedule() public {
        require(now <= expiration, "This contract has expired");
        require(eta == 0, "This spell has already been scheduled");
        eta = now + DSPauseAbstract(pause).delay();
        pause.plot(action, tag, sig, eta);
    }

    function cast() public {
        require(!done, "spell-already-cast");
        done = true;
        pause.exec(action, tag, sig, eta);
    }
}
