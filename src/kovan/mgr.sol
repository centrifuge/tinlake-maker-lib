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

interface VowLike {
    function fess(uint256) external;
}

interface VatLike {
    function live() external view returns (uint);
    function slip(bytes32,address,int) external;
    function flux(bytes32,address,address,uint256) external;
    function ilks(bytes32) external returns (uint,uint,uint,uint,uint);
    function urns(bytes32,address) external returns (uint,uint);
    function move(address,address,uint) external;
    function frob(bytes32,address,address,address,int,int) external;
    function grab(bytes32,address,address,address,int256,int256) external;
    function gem(bytes32,address) external returns (uint);
    function hope(address) external;
}

interface RedeemLike {
    function redeemOrder(uint) external;
    function disburse(uint) external returns (uint,uint,uint,uint);
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
    mapping (address => uint) public wards;
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

    uint public tab;  // Dai written off
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

    uint public constant dec = 18;

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

        dai.approve(daiJoin_, uint(-1));
        vat.hope(daiJoin_);
        gem.approve(pool_, uint(-1));
        gem.approve(tranche, uint(-1));
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
        require(safe && live);
        require(int(wad) >= 0, "TinlakeManager/overflow");
        gem.transferFrom(msg.sender, address(this), wad);
        vat.slip(ilk, address(this), int(wad));
        vat.frob(ilk, address(this), address(this), address(this), int(wad), 0);
    }

    function exit(uint wad) public ownerOnly note {
        require(safe && live);
        require(wad <= 2 ** 255, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), -int(wad), 0);
        vat.slip(ilk, address(this), -int(wad));
        gem.transfer(msg.sender, wad);
    }

    // draw & wipe call daiJoin.exit/join immediately
    function draw(uint wad) public ownerOnly note {
        require(safe && live);
        (,uint rate, , , ) = vat.ilks(ilk);
        uint dart = divup(mul(ONE, wad), rate);
        require(int(dart) >= 0, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), 0, int(dart));
        daiJoin.exit(msg.sender, wad);
    }

    function wipe(uint wad) public ownerOnly note {
        require(safe && live);
        dai.transferFrom(msg.sender, address(this), wad);
        daiJoin.join(address(this), wad);
        (,uint rate, , , ) = vat.ilks(ilk);
        uint dart = mul(ONE, wad) / rate;
        require(dart <= 2 ** 255, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this), 0, -int(dart));
    }

    // --- Administration ---
    function setOwner(address newOwner) external ownerOnly note {
        owner = newOwner;
    }

    function migrate(address dst) public auth note {
        vat.hope(dst);
        dai.approve(dst, uint(-1));
        gem.approve(dst, uint(-1));
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

    function unwind(uint endEpoch) public note {
        require(!safe && glad && live, "TinlakeManager/not-soft-liquidation");
        (uint redeemed, , ,uint remainingDrop) = pool.disburse(endEpoch);
        uint dropReturned = sub(vat.gem(ilk, address(this)), remainingDrop);
        require(dropReturned <= 2 ** 255, "TinlakeManager/overflow");

        (, uint rate, , ,) = vat.ilks(ilk);
        (, uint art) = vat.urns(ilk, address(this));
        uint cdptab = mul(art, rate);

        uint payBack = min(redeemed, divup(cdptab, ONE));

        daiJoin.join(address(this), payBack);

        // Repay dai debt up to the full amount
        // and exit the gems used up
        uint dart = mul(ONE, payBack) / rate;
        require(dart <= 2 ** 255, "TinlakeManager/overflow");
        vat.frob(ilk, address(this), address(this), address(this),
                 -int(dropReturned), -int(dart));
        vat.slip(ilk, address(this), -int(dropReturned));

        // Return possible remainder to the owner
        dai.transfer(owner, dai.balanceOf(address(this)));
    }

    // --- Writeoff ---
    function sink() public note auth {
        require(!safe && glad && live);
        (uint256 ink, uint256 art) = vat.urns(ilk, address(this));
        require(ink <= 2 ** 255, "TinlakeManager/overflow");
        require(art <= 2 ** 255, "TinlakeManager/overflow");
        (, uint rate, , ,) = vat.ilks(ilk);
        vat.grab(ilk,
                 address(this),
                 address(this),
                 address(vow),
                 -int(ink),
                 -int(art));
        vat.slip(ilk, address(this), -int(ink));
        tab = mul(rate, art);
        vow.fess(tab);
        glad = false;
    }

    function recover(uint endEpoch) public note {
        require(!glad && live, "TinlakeManager/not-written-off");

        (uint recovered, , ,) = pool.disburse(endEpoch);

        uint payBack = min(recovered, tab / ONE);
        daiJoin.join(address(vow), payBack);
        tab = sub(tab, mul(payBack, ONE));
        dai.transfer(owner, dai.balanceOf(address(this)));
    }

    // --- Global settlement ---
    function take(uint endEpoch) public note ownerOnly {
        require(!live, "TinlakeManager/not-live");
        pool.disburse(endEpoch);
        dai.transfer(msg.sender, dai.balanceOf(address(this)));
    }

    function cage() external note {
        require(wards[msg.sender] == 1 || vat.live() == 0, "TinlakeManager/not-authorized");
        live = false;
    }
}
