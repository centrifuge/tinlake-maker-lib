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


    // MIP21 contracts CF4003_A
    address public constant MCD_JOIN = 0xe0cc2873A586DdFf4fAf1cb626624303e20A19a6;
    address constant GEM = 0x49cb575Bc07FC9916dC828442A27223353C37e1e;
    address public constant OPERATOR = 0x45e17E350279a2f28243983053B634897BA03b64; // MGR
    address public constant INPUT_CONDUIT = 0x45e17E350279a2f28243983053B634897BA03b64; // MGR
    address public constant OUTPUT_CONDUIT = 0x45e17E350279a2f28243983053B634897BA03b64; // MGR
    address public constant URN =  0x3C8f85f9D57a57d1B01d3F42E026600aE6d17bEA;
    address public LIQ = 0x2881c5dF65A8D81e38f7636122aFb456514804CC; // MIP21-LIQ-ORACLE

    // changelog IDs
    bytes32 public constant dropID = "RWA005";
    bytes32 public constant joinID = "MCD_JOIN_RWA005_A";
    bytes32 public constant urnID = "RWA005_A_URN";
    bytes32 public constant inputConduitID = "RWA005_A_INPUT_CONDUIT";
    bytes32 public constant outputConduitID = "RWA005_A_OUTPUT_CONDUIT";
    bytes32 public constant pipID = "PIP_RWA005";

    // values, based on https://forum.makerdao.com/t/fft1-drop-collateral-onboarding-risk-evaluation/8036
    bytes32 public constant ilk = "RWA005-A";
    // look up in https://ipfs.io/ipfs/QmefQMseb3AiTapiAKKexdKHig8wroKuZbmLtPLv4u2YwW
    uint256 public constant RATE = 1000000001395766281313196627; // 4.5% stability fee
    uint256 public constant DC = 15 * MILLION * RAD; // creditline: 15 mio
    uint256 public constant INITIAL_PRICE =  16_380_375 * WAD; // creditLine + 2 years of stability fee => 15000000 * 1.045^2
}
