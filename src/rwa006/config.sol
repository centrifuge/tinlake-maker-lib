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

    // Tinlake addresses P1 
    address constant ROOT = 0x09E5b61a15526753b8aF01e21Bd3853146472080;
    address constant DROP = 0x0bDAA77Ba1cb0E7dAf18963A8f202Da077e867bA;
    address constant MGR = 0x652A3B3b91459504A8D1d785B0c923A34D638218;
    address constant RESERVE = 0x1819b65d89dF1ABCe2Dcf32426f3665e82358562;
    address constant MEMBERLIST = 0x1b8413C9b1B93aFfa2fC04637778b810a9E2a8b2;
    address constant COORDINATOR = 0x671954B36350D6B3f1427f1a3CD64C8eb6845913; 
    address constant SENIOR_OPERATOR = 0xf50B1E1b4B1C4083D6411b9b29e7039973feb247;
    address constant ASSESSOR = 0x24a63EAb481C07142A197b2DDc82fAfF011507Bc;
    address constant TRANCHE = 0x8abd1183a606C44548e51d102d60adB9C4dce3BD;


    // MIP21 contracts RWA006-A
    address public constant MCD_JOIN = 0x039B74bD0Adc35046B67E88509900D41b9D95430;
    address constant GEM = 0x4E65F06574F1630B4fF756C898Fe02f276D53E86;
    address public constant OPERATOR = 0x652A3B3b91459504A8D1d785B0c923A34D638218; // MGR
    address public constant INPUT_CONDUIT = 0x652A3B3b91459504A8D1d785B0c923A34D638218; // MGR
    address public constant OUTPUT_CONDUIT = 0x652A3B3b91459504A8D1d785B0c923A34D638218; // MGR
    address public constant URN =  0x6fa6F9C11f5F129f6ECA4B391D9d32038A9666cD;
    address public LIQ = 0x2881c5dF65A8D81e38f7636122aFb456514804CC; // MIP21-LIQ-ORACLE

    // changelog IDs
    bytes32 public constant dropID = "RWA006";
    bytes32 public constant joinID = "MCD_JOIN_RWA006_A";
    bytes32 public constant urnID = "RWA006_A_URN";
    bytes32 public constant inputConduitID = "RWA006_A_INPUT_CONDUIT";
    bytes32 public constant outputConduitID = "RWA006_A_OUTPUT_CONDUIT";
    bytes32 public constant pipID = "PIP_RWA006";

    // values, based on https://forum.makerdao.com/t/p1-drop-mip6-risk-assessment-alternative-equity-advisors-drop-us-agricultural-real-estate/8232
    bytes32 public constant ilk = "RWA006-A";
    // look up in https://ipfs.io/ipfs/QmefQMseb3AiTapiAKKexdKHig8wroKuZbmLtPLv4u2YwW
    uint256 public constant RATE = 1000000000627937192491029810; // 2% stability fee
    uint256 public constant DC = 20 * MILLION * RAD; // creditline: 20 mio
    uint256 public constant MAT = 100 * RAY / 100; // Min Vault CR of 100%
    uint256 public constant INITIAL_PRICE =  20_808_000 * WAD; // creditLine + 2 years of stability fee => 20000000 * 1.02^2
}
