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
// It manages only one cdp and only has one owner. It can not recover
// from a liquidatio and needs to be redeployed after it has gone
// into an unsafe or unhealthy state.

// It manages only one urn, and can enter two stages of liquidation:
// 1) A 'soft' liquidation (tell + unwind), in which drop is send to the pool
// to redeem DROP for DAI to reduce cdp debt.

// 2) A 'hard' liquidation (kick + recover), triggered by a `cat.bite`, in which
// dai redeemed goes to cover vow sin.

// Note that the internal gem created as a result of `join` through this manager is
// not only DROP as an ERC20 balance in this contract, but also what's currently
// undergoing redemption from the Tinlake pool.

contract TinlakeMgr {
    bool public safe; // In normal operation
    bool public healthy; // In normal operation
    bool public live; // In normal operation

    uint public gem; // DROP in Maker
    uint public tab;  // DAI owed to vow

    address public vow;
    RedeemLike  public pool; // TODO: make constant
    GemLike     public drop;
    GemJoinLike public daiJoin;

    constructor(address vat_, bytes32 ilk_, address gem_, address pool_, address owner_) public {
        wards[msg.sender] = 1;

        pool = RedeemLike(pool_);
        owner = owner_;

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

    // --- Only allow certain interactions from the owner ---
    modifier ownerOnly() { require(msg.sender == owner, "TinlakeMgr/owner-only"); _; }

    // --- Vault Operation---
    // join & exit move the gem directly into/from the urn
    function exit(address usr, uint wad) external ownerOnly note {
        require(safe && healthy && live);
        require(wad <= 2 ** 255, "TinlakeManager/overflow");
        gem = sub(gem, wad);
        vat.slip(ilk, owner, -int(wad));
        vat.frob(ilk, address(this), address(this), -int(wad), 0);
        require(gem.transfer(usr, share), "TinlakeManager/failed-transfer");
    }

    function join(address usr, uint wad) public ownerOnly note {
        require(safe && healthy && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        gem = add(gem, wad);
        vat.slip(ilk, usr, int(wad));
        vat.frob(ilk, address(this), address(this), int(wad), 0);
        require(gem.transferFrom(owner, address(this), wad), "GemJoin/failed-transfer");
    }

    // draw & wipe call daiJoin.exit/join immediately
    function draw(uint wad) ownerOnly {
        require(safe && healthy && live);
        vat.frob(ilk, address(this), address(this), 0, wad);
        daiJoin.exit(owner, wad);
    }

    function wipe(uint wad) {
        require(safe && healthy && live);
        require(wad <= 2 ** 255, "TinlakeManager/overflow");

        daiJoin.join(address(this), wad);
        vat.frob(ilk, address(this), address(this), 0, -int(wad));
    }


    // --- Soft Liquidations ---
    function tell() public auth note {
        safe = false;
        debt = gem.balanceOf(address(this);
        pool.redeemOrder(debt);
    }

    function unwind(uint endEpoch) public note {
        require(healthy && !safe, "TinlakeManager/not-soft-liquidation")
        // (payoutCurrencyAmount, payoutTokenAmount, remainingSupplyCurrency, remainingRedeemToken);
        (uint daiReturned, _, _, uint remainingDrop) = pool.disburse();
        dropReturned = -int(sub(debt, remainingDrop));
        debt = remainingDrop;

        // Calculate DAI debt
        (uint art, ) = vat.urns(ilk, urn);
        ( , uint rate, , ,) = vat.ilks(ilk);
        uint dtab = mul(art, rate);
        uint payBack = max(returned, divup(dtab, ONE));

        daiJoin.join(address(this), payback);

        // if (art > 0) { should always call it
        vat.frob(ilk, urn, address(this), address(this), address(this),
                 dropReturned, -int(mul(payBack, ONE)));
        // }
        vat.slip(ilk, address(this), dropReturned);
        dai.transfer(dai.balanceOf(address(this)), owner);
    }

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
        // We move the gem into this adapter mostly for cosmetic reasons.
        // There is no use for it anymore in the system. It would be
        // cleaner to reduce it in `take` using `vat.slip()`
        vat.flux(ilk, msg.sender, address(this), lot);
        dropJoin.exit(address(this), lot);
        pool.redeemOrder(drop.balanceOf(address(this)));
        emit Kick(id, lot, bid, tab_, dest, vow);
    }

    function recover() public {
        require(!healthy, "TinlakeManager/Pool-healhty");
        (uint returned, _, _, uint dropRemaining) = pool.disburse();

        uint tabWad = tab / RAY; // always rounds down, this could lead to < 1 RAY to be lost in dust
        if (tabWad < returned) {
            dai.transfer(owner, sub(returned, tabWad));
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
