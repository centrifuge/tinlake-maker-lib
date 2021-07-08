pragma solidity >=0.5.12;

contract POOL_CONFIG {

    // precision
    uint256 constant public THOUSAND = 10 ** 3;
    uint256 constant public MILLION  = 10 ** 6;
    uint256 constant public WAD      = 10 ** 18;
    uint256 constant public RAY      = 10 ** 27;
    uint256 constant public RAD      = 10 ** 45;

    // Maker changelog 
    address constant MAKER_CHANGELOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;

    // Tinlake addresses FF1 
    address constant ROOT = 0x68CA1a0411a8137d8505303A5745aa3Ead87ba6C;
    address constant DROP = 0x0f763b4d5032f792fA39eE54BE5422592eC8329B;
    address constant MGR = 0x17E5954Cdd3611Dd84e444F0ed555CC3a06cB319;
    address constant RESERVE = 0x1151934d5DA82da4c27CF33AbB98b0b626465cb7;
    address constant MEMBERLIST = 0x8a9C850D7214ca626f4B12a04759dF9A2a9A51b9;
    address constant COORDINATOR = 0x38721a32dDa9d6EC6a5c135243C93e7ca56Bde86; 
    address constant SENIOR_OPERATOR = 0x63c6883d8fEDE11286007EA080A69f584f27b4a1;
    address constant ASSESSOR = 0xac7582C83bb4730bB3F9537A20f73B380B59787C;
    address constant TRANCHE = 0x63c6883d8fEDE11286007EA080A69f584f27b4a1;


    // MIP21 contracts FF1004-A
    address public constant MCD_JOIN = 0x19443a936b99c5c88897aE3eF72d65EcE6a9e4B8;
    address constant GEM = 0x4bA1b1A2876bF7E740eedA5e43D0310f2DF368A9;
    address public constant OPERATOR = 0x17E5954Cdd3611Dd84e444F0ed555CC3a06cB319; // MGR
    address public constant INPUT_CONDUIT = 0x17E5954Cdd3611Dd84e444F0ed555CC3a06cB319; // MGR
    address public constant OUTPUT_CONDUIT = 0x17E5954Cdd3611Dd84e444F0ed555CC3a06cB319; // MGR
    address public constant URN =  0x9afcF6d0E31d55Eec4dC379e8504636B1d67BBE2;
    address public LIQ = 0x2881c5dF65A8D81e38f7636122aFb456514804CC; // MIP21-LIQ-ORACLE

    // changelog IDs
    bytes32 public constant dropID = "FF1004";
    bytes32 public constant joinID = "MCD_JOIN_FF1004_A";
    bytes32 public constant urnID = "FF1004_A_URN";
    bytes32 public constant inputConduitID = "FF1004_A_INPUT_CONDUIT";
    bytes32 public constant outputConduitID = "FF1004_A_OUTPUT_CONDUIT";
    bytes32 public constant pipID = "PIP_FF1004";

    // values, based on https://forum.makerdao.com/t/fft1-drop-collateral-onboarding-risk-evaluation/8036
    bytes32 public constant ilk = "FF1004-A";
    // look up in https://ipfs.io/ipfs/QmefQMseb3AiTapiAKKexdKHig8wroKuZbmLtPLv4u2YwW
    uint256 public constant RATE = 1000000001395766281313196627; // 4.5% stability fee
    uint256 public constant DC = 15 * MILLION * RAD; // creditline: 15 mio
    uint256 public constant MAT = 105 * RAY / 100; // Min Vault CR of 105%
    uint256 public constant INITIAL_PRICE =  16_380_375 * WAD; // creditLine + 2 years of stability fee => 15000000 * 1.045^2
}
