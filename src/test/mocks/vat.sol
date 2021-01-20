// Copyright (C) 2020 Centrifuge
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
pragma solidity >=0.5.15 <0.6.0;
import "ds-test/test.sol";

import "../../../lib/tinlake/src/test/mock/mock.sol";
import "./auth.sol";

contract VatMock is Mock, Auth {
    mapping (bytes32 => int) public values_int;

    constructor() public {
        wards[msg.sender] = 1;
        values_uint["live"] = 1;

    }

    function urns(bytes32, address) external returns (uint, uint) {
        calls["urns"]++;
        return (values_uint["ink"], values_uint["tab"]);
    }

    function hope(address usr) external { 
        calls["hope"]++;  
    }

    function slip(bytes32 ilk, address usr, int256 wad) external auth {
        calls["slip"]++;
        values_address["slip_usr"] = usr;
        values_bytes32["slip_ilk"] = ilk;
        values_int["slip_wad"] = wad;
    }

    function frob(bytes32 i, address u, address v, address w, int dink, int dart) external { 
        calls["frob"]++;     
        values_bytes32["frob_i"] = i;
        values_address["frob_u"] = u;
        values_address["frob_v"] = v;
        values_address["frob_w"] = w;
        values_int["frob_dink"] = dink;
        values_int["frob_dart"] = dart;
        // set values check calls  
    }

    function live() external returns (uint) {
       // emit log_named_uint("haha", 100);
        return values_uint["live"];
    }

    // unit test helpers
    function setLive(uint live) external {
        emit log_named_uint("haha", 100);
        values_uint["live"] = live;
    }

    // unit test helpers
    function setInk(uint wad) external {
        values_uint["ink"] = wad;
    }

    function increaseTab(uint wad) external {
        values_uint["tab"] = safeAdd(values_uint["tab"], wad);
    }

    function decreaseTab(uint wad) external {
        values_uint["tab"] = safeSub(values_uint["tab"], wad);
    }
}
