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
}

interface GemJoinLike {
    function join(address,uint) external;
    function exit(address,uint) external;
}

interface VatLike {
    function slip(bytes32,address,int) external;
    function urns(bytes32,bytes32) external returns (uint,uint);
    function move(address,address,uint) external;
}

interface RedeemLike {
    function redeemOrder(uint) external;
    function disburse() external returns (uint,uint);
}

// This contract is (or will become) essentially a merge of
// flip, join and a cdp-manager.
// It manages only one cdp.

// It manages only one cdp, and can enter two stages of liquidation:
// 1) A 'soft' liquidation (unwind + recover), in which drop is send to the pool
// to redeem dai to reduce cdp debt.

// 2) A 'hard' liquidation (kick + recover), triggered by a `cat.bite`, in which
// dai redeemed goes to cover vow sin.

// Note that the internal gem created as a result of `join` through this manager is
// not pure drop, but rather `drop` in this contract + what's currently undergoing soft liquidiation.
contract TinlakeMgr{
    bool public safe; // In normal operation
    bool public healthy; // In normal operation
    bool public live; // In normal operation

    uint public gem; // DROP in Maker
    uint public tab;  // DAI owed to vow

    address public vow;
    RedeemLike  public pool; // TODO: make constant
    GemLike     public drop;
    GemJoinLike public daiJoin;

    constructor(address vat_, bytes32 ilk_, address gem_, address pool_, address user_) public {
        pool = RedeemLike(pool_);
        user = user_;

        safe = true;
        healthy = true;
        live = true;

        drop = GemLike(drop_);
        daiJoin = GemJoinLike(daiJoin_);
        dai.approve(daiJoin_, uint(-1));
        drop.approve(pool_, uint(-1));
    }

    // --- Math ---
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x);
    }
    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x);
    }
    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Only allow certain interactions from the user ---
    modifier userOnly() { require(msg.sender == user, "TinlakeMgr/user-only"); _; }

    // --- Vault Operation---
    function exit(address usr, uint wad) external userOnly note {
        require(wad <= 2 ** 255, "TinlakeManager/overflow");
        gem = sub(gem, wad);
        vat.slip(ilk, user, -int(wad));
        require(gem.transfer(usr, share), "TinlakeManager/failed-transfer");
    }

    function join(address usr, uint wad) public userOnly note {
        require(live == 1, "TinlakeManager/not-live");
        require(int(wad) >= 0, "TinlakeManager/overflow");
        gem = add(gem, wad);
        vat.slip(ilk, usr, int(wad));
        require(gem.transferFrom(user, address(this), wad), "GemJoin/failed-transfer");
    }

    function draw() userOnly {
        require(safe && healthy && live);

    }
    function wipe() {
        require(safe && healthy && live);
    }


    // --- Soft Liquidations ---
    function seize() public auth note {
        safe = false;
    }

    function unwind() public note {
        require(healthy && !safe, "TinlakeManager/not-soft-liquidation")
        debt = gem.balanceOf(address(this);
        pool.redeemOrder(debt);
    }

    function recover() public note {
        require(healthy && !safe, "TinlakeManager/not-soft-liquidation")
        (uint daiReturned, uint dropReturned ) = pool.disburse();
        debt = sub(debt, dropReturned);

        (uint art, ) = vat.urns(ilk, urn);
        ( , uint rate, , ,) = vat.ilks(ilk);
        uint dtab = mul(art, rate);
        uint payBack = max(returned, divup(dtab, ONE));

        daiJoin.join(address(this), payback);

        if (art > 0) {
            vat.frob(ilk, urn, address(this), address(this), address(this), 0, -int(mul(payBack, ONE)));
        }
        dai.transfer(dai.balanceOf(address(this)), user);


    // --- Writeoff ---
    // called by the Cat, creates `sin` in the `vow` and attempts
    // to recover from the pool over time.
    //
    function kick(address dest_, address gal, uint256 tab_, uint256 lot, uint256 bid)
        public auth returns (uint256 id)
    {
        healthy = false;
        vow = gal;
        tab = tab_;
        vat.flux(ilk, msg.sender, address(this), lot);
        dropJoin.exit(address(this), lot);
        pool.redeemOrder(drop.balanceOf(address(this)));
        emit Kick(id, lot, bid, tab_, dest, vow);
    }

    function take() public {
        require(!healthy, "TinlakeManager/Pool-healhty");
        (uint returned, ) = pool.disburse();
        uint tabWad = tab / RAY; // always rounds down, this could lead to < 1 RAY to be lost in dust
        if (tabWad < returned) {
            dai.transfer(user, sub(returned, tabWad));
            returned = tabWad;
        }
        if (tab != 0) {
            daiJoin.join(vow, returned);
            tab = sub(tab, mul(returned, RAY));
        }
    }


    // --- End ---
    function cage() external note auth {
        live = false;
    }


}
