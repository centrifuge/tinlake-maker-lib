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

import "./lib.sol";

interface VatLike {
    function move(address,address,uint256) external;
    function flux(bytes32,address,address,uint256) external;
}

interface RedeemLike {
    function redeemOrder(uint, uint) public;

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
    DROPJoinLike      public dropJoin;

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
    constructor(address vat_, bytes32 ilk_) public {
        vat = VatLike(vat_);
        ilk = ilk_;
        wards[msg.sender] = 1;
    }

    // --- Math ---
    function sub(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x - y) <= x);
    }

    // --- Auction ---
    function kick(address dest_, address gal, uint256 tab, uint256 lot, uint256 bid)
        public auth returns (uint256 id)
    {
        vow = gal;
        dest = dest_;
        vat.flux(ilk, msg.sender, address(this), lot);

        dropJoin.exit(address(this), lot);
        pool.redeemOrder(lot);
        emit Kick(id, lot, bid, tab, dest, vow);
    }

    function take() public {
        uint returned, _ = pool.disburse();
        if (tab < returned) {
            dai.transferFrom(address(this), usr, sub(returned-tab));
            returned = tab;
        }
        if (tab != 0) {
            dai.join(vow, returned);
            tab = sub(tab, returned);
        }
    }
}
