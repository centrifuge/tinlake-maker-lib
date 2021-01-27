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
    function decimals() external view returns (uint256);
    function transfer(address,uint256) external returns (bool);
    function transferFrom(address,address,uint256) external returns (bool);
    function approve(address,uint256) external returns (bool);
    function totalSupply() external returns (uint256);
    function balanceOf(address) external returns (uint256);
}

interface GemJoinLike {
    function join(address,uint256) external;
    function exit(address,uint256) external;
}

interface VowLike {
    function fess(uint256) external;
}

interface VatLike {
    function live() external view returns (uint256);
    function slip(bytes32,address,int256) external;
    function flux(bytes32,address,address,uint256) external;
    function ilks(bytes32) external returns (uint256,uint256,uint256,uint256,uint256);
    function urns(bytes32,address) external returns (uint256,uint256);
    function move(address,address,uint256) external;
    function frob(bytes32,address,address,address,int256,int256) external;
    function grab(bytes32,address,address,address,int256,int256) external;
    function gem(bytes32,address) external returns (uint256);
    function hope(address) external;
}

interface RedeemLike {
    function redeemOrder(uint256) external;
    function disburse(uint256) external returns (uint256,uint256,uint256,uint256);
}

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
    mapping (address => uint256) public wards;
    function rely(address usr) external note auth { require(live, "TinlakeMgr/not-live"); wards[usr] = 1; }
    function deny(address usr) external note auth { require(live, "TinlakeMgr/not-live"); wards[usr] = 0; }
    modifier auth {
        require(wards[msg.sender] == 1, "TinlakeMgr/not-authorized");
        _;
    }

    modifier ownerOnly {
        require(msg.sender == owner, "TinlakeMgr/owner-only");
        _;
    }

    // The owner manages the cdp, but is not authorized to call kick or cage.
    address public owner;

    bool public safe; // Soft liquidation not triggered
    bool public glad; // Write-off not triggered
    bool public live; // Global settlement not triggered

    uint256 public tab;  // Dai written off
    bytes32 public ilk; // Constant (TODO: hardcode)

    // --- Contracts ---
    // These can all be hardcoded upon release.
    // dss components
    VatLike public vat;
    GemLike public dai;
    VowLike public vow;
    GemJoinLike public daiJoin;

    // Tinlake components
    GemLike      public gem;
    GemLike      public tin;
    RedeemLike   public pool;

    uint256 public constant dec = 18;

    constructor(address vat_,      address dai_,
                address daiJoin_,  address vow_,
                address drop_,     address pool_,
                address owner_,    address tranche,
                bytes32 ilk_) public {

        vat = VatLike(vat_);
        dai = GemLike(dai_);
        vow = VowLike(vow_);
        daiJoin = GemJoinLike(daiJoin_);

        gem = GemLike(drop_);
        pool = RedeemLike(pool_);

        ilk = ilk_;
        wards[msg.sender] = 1;

        owner = owner_;

        safe = true;
        live = true;
        glad = true;

        dai.approve(daiJoin_, uint256(-1));
        vat.hope(daiJoin_);
        gem.approve(pool_, uint256(-1));
        gem.approve(tranche, uint256(-1));
    }

    // --- Math ---
    uint256 constant RAY = 10 ** 27;
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x);
    }
    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x);
    }
    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }
    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x > y ? y : x;
    }

    // --- Vault Operation---
    // join & exit move the gem directly into/from the urn
    function join(uint256 wad) public ownerOnly note {
        require(safe && live);
        require(int256(wad) >= 0, "TinlakeManager/overflow");
        gem.transferFrom(msg.sender, address(this), wad);
        vat.slip(ilk, address(this), int256(wad));
        vat.frob(ilk, address(this), address(this), address(this), int256(wad), 0);
    }

    function exit(uint256 wad) public ownerOnly note {
        require(safe && live);
        require(wad <= 2 ** 255, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), -int256(wad), 0);
        vat.slip(ilk, address(this), -int256(wad));
        gem.transfer(msg.sender, wad);
    }

    // draw & wipe call daiJoin.exit/join immediately
    function draw(uint256 wad) public ownerOnly note {
        require(safe && live);
        (, uint256 rate, , , ) = vat.ilks(ilk);
        uint256 dart = divup(mul(RAY, wad), rate);
        require(int256(dart) >= 0, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), 0, int256(dart));
        daiJoin.exit(msg.sender, wad);
    }

    function wipe(uint256 wad) public ownerOnly note {
        require(safe && live);
        dai.transferFrom(msg.sender, address(this), wad);
        daiJoin.join(address(this), wad);
        (,uint256 rate, , , ) = vat.ilks(ilk);
        uint256 dart = mul(RAY, wad) / rate;
        require(dart <= 2 ** 255, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), 0, -int256(dart));
    }

    // --- Administration ---
    function setOwner(address newOwner) external ownerOnly note {
        owner = newOwner;
    }

    function migrate(address dst) public auth note {
        vat.hope(dst);
        dai.approve(dst, uint256(-1));
        gem.approve(dst, uint256(-1));
        live = false;
    }

    // --- Liquidation ---
    function tell() public note {
        require(safe);
        require(wards[msg.sender] == 1 || (msg.sender == owner && !live), "TinlakeManager/not-authorized");
        (uint256 ink, ) = vat.urns(ilk, address(this));
        safe = false;
        pool.redeemOrder(ink);
    }

    function unwind(uint256 endEpoch) public note {
        require(!safe && glad && live, "TinlakeManager/not-soft-liquidation");
        (uint256 redeemed, , ,uint256 remainingDrop) = pool.disburse(endEpoch);
        (uint256 ink, ) = vat.urns(ilk, address(this));
        uint256 dropReturned = sub(ink, remainingDrop);
        require(dropReturned <= 2 ** 255, "TinlakeManager/overflow");

        (, uint256 rate, , ,) = vat.ilks(ilk);
        (, uint256 art) = vat.urns(ilk, address(this));
        uint256 cdptab = mul(art, rate);
        uint256 payBack = min(redeemed, divup(cdptab, RAY));

        daiJoin.join(address(this), payBack);
        // Repay dai debt up to the full amount
        // and exit the gems used up
        uint256 dart = mul(RAY, payBack) / rate;
        require(dart <= 2 ** 255, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this),
                 0, -int256(dart));
        vat.grab(ilk, address(this), address(this), address(this),
                 -int256(dropReturned), 0);
        vat.slip(ilk, address(this), -int256(dropReturned));
        // Return possible remainder to the owner
        dai.transfer(owner, dai.balanceOf(address(this)));
    }

    // --- Writeoff ---
    function sink() public note auth {
        require(!safe && glad && live);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        require(ink <= 2 ** 255, "TinlakeManager/overflow");
        require(art <= 2 ** 255, "TinlakeManager/overflow");
        (, uint256 rate, , ,) = vat.ilks(ilk);
        vat.grab(ilk,
                 address(this),
                 address(this),
                 address(vow),
                 -int256(ink),
                 -int256(art));
        vat.slip(ilk, address(this), -int256(ink));
        tab = mul(rate, art);
        vow.fess(tab);
        glad = false;
    }

    function recover(uint256 endEpoch) public note {
        require(!glad, "TinlakeManager/not-written-off");

        (uint256 recovered, , ,) = pool.disburse(endEpoch);
        uint256 payBack = min(recovered, tab / RAY);
        daiJoin.join(address(vow), payBack);
        tab = sub(tab, mul(payBack, RAY));
        dai.transfer(owner, dai.balanceOf(address(this)));
    }

    function cage() external note {
        require(!glad);
        require(wards[msg.sender] == 1 || vat.live() == 0, "TinlakeManager/not-authorized");
        live = false;
    }
}
