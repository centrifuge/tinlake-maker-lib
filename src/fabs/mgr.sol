// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity =0.5.12;

import { TinlakeManager } from "./../mgr.sol";

interface TinlakeManagerFabLike {
    function newTinlakeManager(address, address, address,  address, address, address, address, address) external returns (address);
}

contract TinlakeManagerFab {
    function newTinlakeManager(address dai_, address daiJoin_, address drop_,  address pool_, address tranche_, address end_, address vat_, address vow_) public returns (address) {
        TinlakeManager mgr = new TinlakeManager(dai_, daiJoin_, drop_,  pool_, tranche_, end_, vat_, vow_);
        mgr.rely(msg.sender);
        mgr.deny(address(this));
        return address(mgr);
    }
}
