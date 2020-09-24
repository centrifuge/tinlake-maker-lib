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
contract TinlakeJoin is GemJoin {

    uint public debt; // drop in redemption
    bool public safe; // In normal operation
    bytes32 public urn; // TODO: should this be handled by a different contract?
    RedeemLike public pool; // TODO: make constant
    GemJoinLike public daiJoin;

    constructor(address vat_, bytes32 ilk_, address gem_, address pool_, bytes32 urn_) public GemJoin(vat_, ilk_, gem_) {
        pool = pool_;
        urn = urn_;
        safe = true;
        daiJoin = GemJoinLike(daiJoin_);
        dai.approve(daiJoin_, uint(-1));
        gem.approve(pool_, uint(-1));
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

    function exit(address usr, uint wad) external note {
        require(wad <= 2 ** 255, "GemJoin/overflow");
        vat.slip(ilk, msg.sender, -int(wad));
        reserves = gem.balanceOf(address(this));
        uint share = mul(wad, reserves) / add(reserves, debt);
        require(gem.transfer(usr, share), "GemJoin/failed-transfer");
    }

    function join(address usr, uint wad) public auth note {
        require(live == 1, "GemJoin/not-live");
        require(int(wad) >= 0, "GemJoin/overflow");
        vat.slip(ilk, usr, int(wad));
        require(gem.transferFrom(msg.sender, address(this), wad), "GemJoin/failed-transfer");
    }

    function draw() ... {
        join();
    }

    function unwind_criteria() public returns (bool) {
        return true; //TBD
    }

    // can only be called by flip
    function seize() public auth note {
        safe = false;
    }

    function unwind(uint wad) public note {
        require(unwind_criteria(), "Unwind criteria not met");
        debt = add(debt, wad);
        pool.redeemOrder(wad);
    }

    function unwind() public {
        unwind(gem.balanceOf(address(this)));
    }

    function recover() public note {
        (uint returned, ) = pool.disburse();

        if (safe) {
            (uint art, ) = vat.urns(ilk, urn);
            ( , uint rate, , ,) = vat.ilks(ilk);
            uint dtab = mul(art, rate);
            uint payBack = max(returned, divup(dtab, ONE));
            daiJoin.join(address(this), payback);

            if (art > 0) {
                vat.frob(ilk, urn, address(this), address(this), address(this), 0, -int(mul(payBack, ONE)));
            }
            dai.transfer(dai.balanceOf(address(this)), address(pool));
        } else {
            daiJoin.join(dai.balanceOf(address(this)), address(flip));
        }
    }
}
