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
        values_uint["rate"] = 10 ** 27;
    }

    function ilks(bytes32) external view returns(uint, uint, uint, uint, uint)  {
        return(0, values_uint["rate"], 0, 0, 0);
    }

    function urns(bytes32, address) external returns (uint, uint) {
        calls["urns"]++;
        return (values_uint["ink"], values_uint["art"]);
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

    function grab(bytes32 i, address u, address v, address w, int dink, int dart) external auth {
        calls["grab"]++;
        values_bytes32["grab_i"] = i;
        values_address["grab_u"] = u;
        values_address["grab_v"] = v;
        values_address["grab_w"] = w;
        values_int["grab_dink"] = dink;
        values_int["grab_dart"] = dart; 
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
        return values_uint["live"];
    }

    function gem(bytes32 ilk, address usr) external returns(uint) {
       return values_uint["gem"];
    }

    // unit test helpers
    function setLive(uint live) external {
        values_uint["live"] = live;
    } 

    function setGem(uint wad) external {
        values_uint["gem"] = wad;
    }

    function setInk(uint wad) external {
        values_uint["ink"] = wad;
    }

    function setArt(uint wad) external {
        values_uint["art"] = wad;
    }
}
