/// flip.sol -- Collateral auction

// Copyright (C) 2018 Rain <rainbreak@riseup.net>
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

import "dss/lib.sol";

interface VatLike {
    function move(address,address,uint256) external;
    function flux(bytes32,address,address,uint256) external;
}

interface RedeemLike {
    function redeemOrder(uint) external;
    function disburse() external returns (uint,uint);
}

interface GemLike {
    function transferFrom(address,address,uint) external returns (bool);
    function transfer(address,uint) external returns (bool);
    function approve(address,uint) external;
    function balanceOf(address) external view returns (uint);
}

interface GemJoinLike {
    function join(address,uint) external;
    function exit(address,uint) external;
}


contract TinlakeFlipper is LibNote {
    // --- Auth ---
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { wards[usr] = 1; }
    function deny(address usr) external note auth { wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "Flipper/not-authorized");
        _;
    }

    // --- Data ---
    VatLike public   vat;            // CDP Engine
    bytes32 public   ilk;            // collateral type

    RedeemLike        public pool;
    GemLike           public dai;
    GemLike           public drop;
    GemJoinLike       public daiJoin;
    GemJoinLike       public dropJoin;

    uint    public tab;
    address public vow;
    address public dest; // where to send excess DAI raised (back to pool)

    // --- Events ---
    event Kick(
      uint256 id,
      uint256 lot,
      uint256 bid,
      uint256 tab,
      address indexed usr,
      address indexed gal
    );

    // --- Init ---
    constructor(address vat_, bytes32 ilk_, address drop_, address dai_, address dropJoin_, address daiJoin_, address pool_, address tranche) public {
        vat = VatLike(vat_);
        ilk = ilk_;

        drop = GemLike(address(drop_));
        dai = GemLike(dai_);

        dropJoin = GemJoinLike(dropJoin_);
        daiJoin = GemJoinLike(daiJoin_);

        pool = RedeemLike(pool_);

        dai.approve(daiJoin_, uint(-1));
        drop.approve(dropJoin_, uint(-1));
        drop.approve(tranche, uint(-1));
        wards[msg.sender] = 1;
    }

    function file(bytes32 what, address data) public auth {
        if (what == "dai") {
        }
    }

    // --- Math ---
    uint constant RAY = 10 ** 27;
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }

    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    // --- Auction ---
    function kick(address dest_, address gal, uint256 tab_, uint256 lot, uint256 bid)
        public auth returns (uint256 id)
    {
        vow = gal;
        dest = dest_;
        tab = tab_;
        vat.flux(ilk, msg.sender, address(this), lot);
        dropJoin.exit(address(this), lot);
        pool.redeemOrder(drop.balanceOf(address(this)));
        emit Kick(id, lot, bid, tab_, dest, vow);
    }

    function take() public {
        (uint returned, ) = pool.disburse();
        uint tabWad = tab / RAY; // always rounds down, this could lead to < 1 RAY to be lost in dust
        if (tabWad < returned) {
            dai.transfer(dest, sub(returned, tabWad));
            returned = tabWad;
        }
        if (tab != 0) {
            daiJoin.join(vow, returned);
            tab = sub(tab, mul(returned, RAY));
        }
    }
}
