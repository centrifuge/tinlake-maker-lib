// Copyright (C) 2020 Martin Lundfall
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

pragma solidity 0.5.12;

import "lib/dss-interfaces/src/dapp/DSPauseAbstract.sol";
import "lib/dss-interfaces/src/dss/VatAbstract.sol";
import "lib/dss-interfaces/src/dss/CatAbstract.sol";
import "lib/dss-interfaces/src/dss/JugAbstract.sol";
import "lib/dss-interfaces/src/dss/SpotAbstract.sol";
import "lib/dss-interfaces/src/dss/OsmAbstract.sol";
import "lib/dss-interfaces/src/dss/OsmMomAbstract.sol";
import "lib/dss-interfaces/src/dss/MedianAbstract.sol";
import "lib/dss-interfaces/src/dss/PotAbstract.sol";
import "lib/dss-interfaces/src/dss/FlipperMomAbstract.sol";

interface MgrAbstract {
    function rely(address) external;
    function drop() external returns (address);
    function vat() external returns (address);
    function vow() external returns (address);
    function assessor() external returns (address);
    function daiJoin() external returns (address);
    function dai() external returns (address);
    function ilk() external returns (bytes32);
}



contract SpellAction {
    // KOVAN ADDRESSES
    //
    // The contracts in this list should correspond to MCD core contracts, verify
    //  against the current release list at:
    //     https://changelog.makerdao.com/releases/kovan/1.0.8/contracts.json

    address constant public MCD_VAT             = 0xbA987bDB501d131f766fEe8180Da5d81b34b69d9;
    address constant public MCD_CAT             = 0x0511674A67192FE51e86fE55Ed660eB4f995BDd6;
    address constant public MCD_VOW             = 0x0F4Cbe6CBA918b7488C26E29d9ECd7368F38EA3b;
    address constant public MCD_JUG             = 0xcbB7718c9F39d05aEEDE1c472ca8Bf804b2f1EaD;
    address constant public MCD_POT             = 0xEA190DBDC7adF265260ec4dA6e9675Fd4f5A78bb;
    address constant public MCD_DAI_JOIN        =	0x5AA71a3ae1C0bd6ac27A1f28e1415fFFB6F15B8c;
    address constant public MCD_DAI	            = 0x4F96Fe3b7A6Cf9725f59d353F723c1bDb64CA6Aa;

    address constant public MCD_SPOT            = 0x3a042de6413eDB15F2784f2f97cC68C7E9750b2D;
    address constant public MCD_END             = 0x24728AcF2E2C403F5d2db4Df6834B8998e56aA5F;
    address constant public FLIPPER_MOM         = 0xf3828caDb05E5F22844f6f9314D99516D68a0C84;
    address constant public OSM_MOM             = 0x5dA9D1C3d4f1197E5c52Ff963916Fe84D2F5d8f3;

    // DROP specific addresses
    // DROP token address 0xTBD
    address constant public MCD_DROP_MGR_A      = address(0xacab);
    address constant public PIP_DROP            = address(0xbabe);
    address constant public DROP                = address(0xcafe);

    // decimals & precision
    uint256 constant public THOUSAND            = 10 ** 3;
    uint256 constant public MILLION             = 10 ** 6;
    uint256 constant public WAD                 = 10 ** 18;
    uint256 constant public RAY                 = 10 ** 27;
    uint256 constant public RAD                 = 10 ** 45;

    // Many of the settings that change weekly rely on the rate accumulator
    // described at https://docs.makerdao.com/smart-contract-modules/rates-module
    // To check this yourself, use the following rate calculation (example 8%):
    //
    // $ bc -l <<< 'scale=27; e( l(1.08)/(60 * 60 * 24 * 365) )'
    //
    uint256 constant public TWELVE_PCT_RATE        = 1000000003593629043335673582;

    function execute() external {
        // Set the global debt ceiling to
        VatAbstract(MCD_VAT).file("Line", VatAbstract(MCD_VAT).Line() + 1 * MILLION * RAD);

        // Set ilk bytes32 variable
        bytes32 DROP_A_ILK = "DROP-A";

        // Sanity checks
        require(MgrAbstract(MCD_DROP_MGR_A).vat() == MCD_VAT, "mgr-vat-not-match");
        require(MgrAbstract(MCD_DROP_MGR_A).ilk() == DROP_A_ILK, "mgr-ilk-not-match");
        require(MgrAbstract(MCD_DROP_MGR_A).drop() == DROP, "mgr-drop-not-match");
        require(MgrAbstract(MCD_DROP_MGR_A).vow() == MCD_VOW, "mgr-vow-not-match");
        require(MgrAbstract(MCD_DROP_MGR_A).dai() == MCD_DAI, "mgr-dai-not-match");
        require(MgrAbstract(MCD_DROP_MGR_A).daiJoin() == MCD_DAI_JOIN, "mgr-daiJoin-not-match");

        // Set price feed for DROP-A
        SpotAbstract(MCD_SPOT).file(DROP_A_ILK, "pip", PIP_DROP);

        // Set the DROP-A flipper in the cat
        CatAbstract(MCD_CAT).file(DROP_A_ILK, "flip", MCD_DROP_MGR_A);

        // Init DROP-A in Vat & Jug
        VatAbstract(MCD_VAT).init(DROP_A_ILK);
        JugAbstract(MCD_JUG).init(DROP_A_ILK);

        // Allow DROP-A manager to modify Vat registry
        VatAbstract(MCD_VAT).rely(MCD_DROP_MGR_A);

        // Allow cat to kick auctions in DROP-A Manager
        // NOTE: this will be reverse later in spell, and is done only for explicitness.
        MgrAbstract(MCD_DROP_MGR_A).rely(MCD_CAT);

        // There is nothing to yank from the manager in end.

        // Allow FlipperMom to access the DROP-A manager
        MgrAbstract(MCD_DROP_MGR_A).rely(FLIPPER_MOM);

        // Update OSM
        MedianAbstract(OsmAbstract(PIP_DROP).src()).kiss(PIP_DROP);
        OsmAbstract(PIP_DROP).rely(OSM_MOM);
        OsmAbstract(PIP_DROP).kiss(MCD_SPOT);
        OsmAbstract(PIP_DROP).kiss(MCD_END);
        OsmMomAbstract(OSM_MOM).setOsm(DROP_A_ILK, PIP_DROP);

        VatAbstract(MCD_VAT).file(DROP_A_ILK,   "line"  , 1 * MILLION * RAD    ); // 1 MM debt ceiling
        VatAbstract(MCD_VAT).file(DROP_A_ILK,   "dust"  , 20 * RAD             ); // 20 Dai dust
        CatAbstract(MCD_CAT).file(DROP_A_ILK,   "lump"  , uint(-1)             ); // Maximum lot size
        CatAbstract(MCD_CAT).file(DROP_A_ILK,   "chop"  , 113 * RAY / 100      ); // 13% liq. penalty
        JugAbstract(MCD_JUG).file(DROP_A_ILK,   "duty"  , TWELVE_PCT_RATE      ); // 12% stability fee
        SpotAbstract(MCD_SPOT).file(DROP_A_ILK, "mat"   , 101 * RAY / 100      ); // 101% coll. ratio
        SpotAbstract(MCD_SPOT).poke(DROP_A_ILK);

        // Execute the first poke in the Osm for the next value
        OsmAbstract(PIP_DROP).poke();

        // Update DROP-A spot value in Vat
        SpotAbstract(MCD_SPOT).poke(DROP_A_ILK);
    }
}

contract DssSpell {
    DSPauseAbstract  public pause =
        DSPauseAbstract(0x8754E6ecb4fe68DaA5132c2886aB39297a5c7189);
    address          public action;
    bytes32          public tag;
    uint256          public eta;
    bytes            public sig;
    uint256          public expiration;
    bool             public done;

    constructor() public {
        sig = abi.encodeWithSignature("execute()");
        action = address(new SpellAction());
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
