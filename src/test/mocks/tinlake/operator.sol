// Copyright (C) 2020 Centrifuge
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

pragma solidity >=0.5.15 <0.6.0;
import "ds-test/test.sol";

import "../../../../lib/tinlake/src/test/mock/mock.sol";
import "./../auth.sol";
import { Dai } from "dss/dai.sol";


contract OperatorMock is Mock, Auth {

    Dai dai;

    constructor(address dai_) public {
        wards[msg.sender] = 1;
        dai = Dai(dai_);
    }

    function redeemOrder(uint wad) public {
        calls["redeemOrder"]++;
        values_uint["redeemOrder_wad"] = wad;
    }

    function disburse(uint endEpoch) external
        returns(uint payoutCurrencyAmount, uint payoutTokenAmount, uint remainingSupplyCurrency,  uint remainingRedeemToken)
    {
        dai.transferFrom(address(this), msg.sender, values_uint["disburse_payoutCurrencyAmount"]);
        return (values_uint["disburse_payoutCurrencyAmount"], values_uint["disburse_payoutTokenAmount"], values_uint["rdisburse_emainingSupplyCurrency"], values_uint["disburse_remainingRedeemToken"]);
    }

    // helper
    function setDisburseValues(uint payoutCurrencyAmount, uint payoutTokenAmount, uint remainingSupplyCurrency,  uint remainingRedeemToken) external {
        values_uint["disburse_payoutCurrencyAmount"] = payoutCurrencyAmount;
        values_uint["disburse_payoutTokenAmount"] =  payoutTokenAmount;
        values_uint["disburse_remainingSupplyCurrency"] = remainingSupplyCurrency;
        values_uint["disburse_remainingRedeemToken"] = remainingRedeemToken;
    }

}
