pragma solidity ^0.5.12;

import "ds-test/test.sol";

import "./TinlakeMakerLib.sol";

contract TinlakeMakerLibTest is DSTest {
    TinlakeMakerLib lib;

    function setUp() public {
        lib = new TinlakeMakerLib();
    }

    function testFail_basic_sanity() public {
        assertTrue(false);
    }

    function test_basic_sanity() public {
        assertTrue(true);
    }
}
