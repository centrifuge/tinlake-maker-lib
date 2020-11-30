/// tinlake_manager.sol -- Tinlake dss adapter

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
import "./lib.sol";

interface GemLike {
    function decimals() external view returns (uint);
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function approve(address,uint) external returns (bool);
    function totalSupply() external returns (uint);
    function balanceOf(address) external returns (uint);
}

interface GemJoinLike {
    function join(address,uint) external;
    function exit(address,uint) external;
}

interface VatLike {
    function slip(bytes32,address,int) external;
    function flux(bytes32,address,address,uint256) external;
    function ilks(bytes32) external returns (uint,uint,uint,uint,uint);
    function urns(bytes32,address) external returns (uint,uint);
    function move(address,address,uint) external;
    function frob(bytes32,address,address,address,int,int) external;
    function gem(bytes32,address) external returns (uint);
    function hope(address) external;
}

interface RedeemLike {
    function redeemOrder(uint) external;
    function disburse(uint) external returns (uint,uint,uint,uint);
}

interface AssessorLike {
    function calcTokenPrices() external returns (uint, uint);
}

import "lib/dss-interfaces/src/dss/FlipAbstract.sol";
// This contract is essentially a merge of
// a join and a cdp-manager.

// It manages only one urn, which can be liquidated in two stages:
// 1) In the first stage, set safe = false and call
// pool.disburse() to try to recover as much dai as possible.

// 2) After the first liquidation period has completed, we either managed to redeem
// enough dai to wipe off all cdp debt, or this debt needs to be written off
// and addded to the sin.

// Note that the internal gem created as a result of `join` through this manager is
// not only DROP as an ERC20 balance in this contract, but also what's currently
// undergoing redemption from the Tinlake pool.

contract TinlakeManager is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { require(live, "mgr/not-live"); wards[usr] = 1; }
    function deny(address usr) external note auth { require(live, "mgr/not-live"); wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "mgr/not-authorized");
        _;
    }
    modifier ownerOnly {
        require(msg.sender == owner, "TinlakeMgr/owner-only");
        _;
    }

    // The owner manages the cdp, but is not authorized to call kick or cage.
    address public owner;

    bool public safe; // Liquidation not triggered
    bool public live; // Global settlement not triggered
    bool public glad; // Write-off not triggered

    uint public limit; // soft liquidiation parameter
    uint public debt; // DROP outstanding (in pool redemption)
    uint public tab;
    bytes32 public ilk; // Constant (TODO: hardcode)

    // --- Contracts ---
    // These can all be hardcoded upon release.
    // dss components
    VatLike public vat;
    FlipAbstract public flip;
    GemLike public dai;
    address public vow;
    GemJoinLike public daiJoin;

    // Tinlake components
    GemLike      public drop;
    GemLike      public tin;
    RedeemLike   public pool;
    AssessorLike public assessor;

    constructor(address vat_,    address dai_,
                address flip_,   address daiJoin_,
                address vow_,    address drop_,
                address pool_,   address tin_,
                address owner_,  address assessor_,
                address tranche, bytes32 ilk_) public {

        vat = VatLike(vat_);
        flip = FlipAbstract(flip_);
        dai = GemLike(dai_);
        vow = vow_;
        daiJoin = GemJoinLike(daiJoin_);

        drop = GemLike(drop_);
        tin = GemLike(tin_);
        pool = RedeemLike(pool_);
        assessor = AssessorLike(assessor_);

        ilk = ilk_;
        wards[msg.sender] = 1;

        owner = owner_;

        safe = true;
        live = true;
        glad = true;

        dai.approve(daiJoin_, uint(-1));
        vat.hope(daiJoin_);
        drop.approve(pool_, uint(-1));
        drop.approve(tranche, uint(-1));
    }

    // --- Math ---
    uint constant ONE = 10 ** 27;
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function divup(uint x, uint y) internal pure returns (uint z) {
        z = add(x, sub(y, 1)) / y;
    }
    function min(uint x, uint y) internal pure returns (uint z) {
        z = x > y ? y : x;
    }

    // --- Vault Operation---
    // join & exit move the gem directly into/from the urn
    function join(uint wad) public ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        drop.transferFrom(msg.sender, address(this), wad);
        vat.slip(ilk, address(this), int(wad));
        vat.frob(ilk, address(this), address(this), address(this), int(wad), 0);
    }

    function exit(address usr, uint wad) public ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), -int(wad), 0);
        vat.slip(ilk, address(this), -int(wad));
        drop.transfer(usr, wad);
    }

    // draw & wipe call daiJoin.exit/join immediately
    function draw(uint wad, address dst) public ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), 0, int(wad));
        daiJoin.exit(dst, wad);
    }

    function wipe(uint wad) public ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        dai.transferFrom(msg.sender, address(this), wad);
        daiJoin.join(address(this), wad);
        vat.frob(ilk, address(this), address(this), address(this), 0, -int(wad));
    }

    // --- Administration
    function file(bytes32 what, uint data) external note auth {
        if (what == "limit") limit = data;
        else revert("Mgr/file-unrecognized-param");
    }

    function file(bytes32 what, FlipAbstract data) external note auth {
        if (what == "flip") flip = data;
        else revert("Mgr/file-unrecognized-param");
    }

    // --- Soft liquidiation condition ---
    function tellCondition() internal returns (bool) {
        (uint juniorPrice, uint seniorPrice) = assessor.calcTokenPrices();

        uint seniorValue = mul(seniorPrice, drop.totalSupply());

        return seniorValue > mul(limit, add(seniorValue, mul(juniorPrice, tin.totalSupply())));
    }

    // --- Liquidation ---
    function tell() public note {
        require(safe && glad && live);
        require(tellCondition() || wards[msg.sender] == 1);
        safe = false;
        uint balance = drop.balanceOf(address(this));
        debt = balance;
        pool.redeemOrder(balance);
    }

    function cdptab() public returns (uint) {
        // Calculate DAI cdp debt
        (, uint art) = vat.urns(ilk, address(this));
        (, uint rate, , ,) = vat.ilks(ilk);
        return mul(art, rate);
    }

    function unwind(uint endEpoch) public note {
        require(glad && !safe && live, "TinlakeManager/not-soft-liquidation");
        (uint redeemed, , ,uint remainingDrop) = pool.disburse(endEpoch);
        uint dropReturned = sub(debt, remainingDrop);
        debt = remainingDrop;

        uint payBack = min(redeemed, divup(cdptab(), ONE));

        daiJoin.join(address(this), payBack);

        // Repay dai debt up to the full amount
        vat.frob(ilk, address(this), address(this), address(this),
                 -int(dropReturned), -int(payBack));

        // Return possible remainder to the owner
        dai.transfer(owner, dai.balanceOf(address(this)));
    }

    // --- Writeoff ---
    // Has the `cat` has bitten the cdp?
    function sad(uint id) public returns (bool) {
        require(flip.kicks() > 0);
        ( , ,address guy , , , , , uint tab_) = flip.bids(id);
        require(guy != address(0));
        tab = tab_; 
        glad = false;
    }

    function recover(uint endEpoch, uint id) public note {
        require(!safe && !glad && live, "TinlakeManager/Pool-healhty");

        (uint returned, , ,uint remainingDrop) = pool.disburse(endEpoch);
        uint dropReturned = sub(debt, remainingDrop);
        debt = remainingDrop;

        // ensure the slip will succeed despite hostile airdrops.
        uint unslip = min(vat.gem(ilk, address(this)), dropReturned);
        vat.slip(ilk, address(this), -int(unslip));

        uint tabWad = tab / ONE; // always rounds down, this could lead to < 1 RAY to be left as dust
        if (tabWad < returned) {
            dai.transfer(owner, sub(returned, tabWad));
            returned = tabWad;
        }
        if (tabWad > 0) {
            daiJoin.join(vow, returned);
            tab = sub(tab, mul(returned, ONE));
        }
    }

    // --- End ---
    function cage() external note auth {
        live = false;
    }
}
