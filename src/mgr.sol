/// tinlake_join.sol -- Tinlake specific GemJoin

// Copyright (C) 2018 Rain <rainbreak@riseup.net>,
// 2019 Lucas Vogelsang <lucas@centrifuge.io>,
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

import {GemJoin} from "dss/join.sol";
import "dss/lib.sol";

interface GemLike {
    function decimals() external view returns (uint);
    function transfer(address,uint) external returns (bool);
    function transferFrom(address,address,uint) external returns (bool);
    function approve(address,uint) external returns (bool);
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
}

interface RedeemLike {
    function redeemOrder(uint) external;
    function disburse(uint) external returns (uint,uint,uint,uint);
}

// This contract is (or will become) essentially a merge of
// flip, join and a cdp-manager.
// It manages only one cdp and only has one owner. It can not recover
// from a liquidatio and needs to be redeployed after it has gone
// into an unsafe or unhealthy state.

// It manages only one urn, which can be liquidated in two stages:
// 1) In the first stage, set safe = false and call
// pool.disburse() to try to recover as much dai as possible.

// 2) After the first liquidation period has completed, we either managed to redeem
// enough dai to wipe off all cdp debt, or this debt needs to be written off
// and addded to the sin.

// Note that the internal gem created as a result of `join` through this manager is
// not only DROP as an ERC20 balance in this contract, but also what's currently
// undergoing redemption from the Tinlake pool.

contract TinlakeMgr is LibNote {
    // --- Auth ---
    mapping (address => uint) public wards;
    function rely(address usr) external note auth { require(live, "mgr/not-live"); wards[usr] = 1; }
    function deny(address usr) external note auth { require(live, "mgr/not-live"); wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "mgr/not-authorized");
        _;
    }

    // The owner manages the cdp, and is not authorized to call tell, kick or cage.
    address public owner;

    bool public safe; // Liquidation not triggered
    bool public glad; // Write-off not triggered
    bool public live; // Global settlement not triggered

    uint public debt; // DROP outstanding (in pool redemption)
    uint public tab;  // DAI owed to vow
    bytes32 public ilk;

    // These can all be hardcoded
    VatLike public vat;
    address public vow;
    GemLike public dai;
    RedeemLike  public pool;
    GemLike     public gem;
    GemJoinLike public daiJoin;

    // --- Events ---
    event Kick(
      uint256 id,
      uint256 lot,
      uint256 bid,
      uint256 tab,
      address indexed usr,
      address indexed gal
    );
    
    constructor(address vat_,  address dai_,  address vow_,
                address pool_, address drop_, address daiJoin_,
                bytes32 ilk_,  address owner_) public {

        vat = VatLike(vat_);
        vow = vow_;
        dai = GemLike(dai_);
        gem = GemLike(drop_);
        daiJoin = GemJoinLike(daiJoin_);

        ilk = ilk_;
        wards[msg.sender] = 1;

        pool = RedeemLike(pool_);
        owner = owner_;

        safe = true;
        glad = true;
        live = true;

        dai.approve(daiJoin_, uint(-1));
        gem.approve(pool_, uint(-1));
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
    function max(uint x, uint y) internal pure returns (uint z) {
        z = x > y ? x : y;
    }

    // --- Only allow certain interactions from the owner ---
    modifier ownerOnly() { require(msg.sender == owner, "TinlakeMgr/owner-only"); _; }

    // --- Vault Operation---
    // join & exit move the gem directly into/from the urn
    function join(address usr, uint wad) public ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        gem.transferFrom(owner, address(this), wad);
        vat.slip(ilk, usr, int(wad));
        vat.frob(ilk, address(this), address(this), address(this), int(wad), 0);
    }

    function exit(address usr, uint wad) external ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        vat.slip(ilk, owner, -int(wad));
        vat.frob(ilk, address(this), address(this), address(this), -int(wad), 0);
        gem.transfer(usr, wad);
    }

    // draw & wipe call daiJoin.exit/join immediately
    function draw(uint wad) public ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), 0, int(wad));
        daiJoin.exit(owner, wad);
    }

    function wipe(uint wad) public ownerOnly note {
        require(safe && glad && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");

        daiJoin.join(address(this), wad);
        vat.frob(ilk, address(this), address(this), address(this), 0, -int(wad));
    }


    // --- Liquidation ---
    function tell() public auth note {
        require(safe && glad && live);
        safe = false;
        debt = add(debt, gem.balanceOf(address(this)));
        pool.redeemOrder(gem.balanceOf(address(this)));
    }

    function unwind(uint endEpoch) public note {
        require(glad && !safe && live, "TinlakeManager/not-soft-liquidation");
        (, , ,uint remainingDrop) = pool.disburse(endEpoch);
        uint dropReturned = sub(debt, remainingDrop);
        debt = remainingDrop; // assert(debt == gem.balanceOf(address(this))

        // Calculate DAI cdp debt
        (uint art, ) = vat.urns(ilk, address(this));
        ( , uint rate, , ,) = vat.ilks(ilk);
        uint daitab = mul(art, rate);

        uint payBack = max(dai.balanceOf(address(this)), divup(daitab, ONE));

        daiJoin.join(address(this), payBack);

        // Repay dai debt up to the full amount
        vat.frob(ilk, address(this), address(this), address(this),
                 -int(dropReturned), -int(payBack));

        // Return possible remainder to the owner
        dai.transfer(owner, dai.balanceOf(address(this)));
    }

    // --- Writeoff ---
    // called by the Cat, creates `sin` in the `vow` and attempts
    // to recover from the pool over time.
    //
    function kick(address dest_, address gal, uint256 tab_, uint256 lot, uint256 bid)
        public auth returns (uint256 id)
    {
        require(live && !safe && glad);
        glad = false;
        vow = gal;
        tab = tab_;
        // We move the gem into this adapter mostly for cosmetic reasons.
        // There is no use for it anymore in the system. It would be
        // cleaner to reduce it in `take` using `vat.slip()`
        vat.flux(ilk, msg.sender, address(this), lot);
        pool.redeemOrder(gem.balanceOf(address(this)));
        emit Kick(id, lot, bid, tab_, dest_, vow);
    }

    function recover(uint endEpoch) public {
        require(!safe && !glad && live, "TinlakeManager/Pool-healhty");
        (uint returned, , ,) = pool.disburse(endEpoch);

        uint tabWad = tab / ONE; // always rounds down, this could lead to < 1 RAY to be lost in dust
        if (tabWad < returned) {
            dai.transfer(owner, sub(returned, tabWad));
            returned = tabWad;
        }
        if (tab != 0) {
            daiJoin.join(vow, returned);
            tab = sub(tab, mul(returned, ONE));
        }

    }

    // needs to be added to support end
    
    /* function bids(uint id) external view returns ( */
    /*     uint256 bid,   // [rad] */
    /*     uint256 lot,   // [wad] */
    /*     address guy, */
    /*     uint48  tic,   // [unix epoch time] */
    /*     uint48  end,   // [unix epoch time] */
    /*     address usr, */
    /*     address gal, */
    /*     uint256 tab    // [rad] */
    /* ); */
    /* function yank(uint id) external; */

    // --- End ---
    function cage() external note auth {
        live = false;
    }
}
