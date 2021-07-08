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

    // Tinlake addresses HTC2 
    address constant ROOT = 0xe4E649e8D591748d7D3031d8001990FCD3E4eba6;
    address constant DROP = 0xe99fb3ec1Ae8f3D7222CcBb83239B30928776c5b;
    address constant MGR = 0x303dFE04Be5731207c5213FbB54488B3aD9B9FE3;
    address constant RESERVE = 0x31AA1ac69d213cc8f2406A6dcF784335481d7e41;
    address constant MEMBERLIST = 0x07edd094A10dBa8D01ad880b843A388747F4E020;
    address constant COORDINATOR = 0xC7379e106aCE86762060860697a918a11A6CaF1A; 
    address constant SENIOR_OPERATOR = 0x05ec25BB56623728e9AAeC6006750E46E631Be03;
    address constant ASSESSOR = 0x29044B7565602e4072b5AC043DAFa5d3bf946f48;
    address constant TRANCHE = 0xd8e2B2C449521a6577fC970F5696F5fA9F2BEB5D;


    // MIP21 contracts RWA004-A
    address public constant MCD_JOIN = 0xa92D4082BabF785Ba02f9C419509B7d08f2ef271;
    address constant GEM = 0x146b0abaB80a60Bfa3b4fDDb5056bBcFa4f1fec1;
    address public constant OPERATOR = 0x303dFE04Be5731207c5213FbB54488B3aD9B9FE3; // MGR
    address public constant INPUT_CONDUIT = 0x303dFE04Be5731207c5213FbB54488B3aD9B9FE3; // MGR
    address public constant OUTPUT_CONDUIT = 0x303dFE04Be5731207c5213FbB54488B3aD9B9FE3; // MGR
    address public constant URN =  0xf22C7F5A2AecE1E85263e3cec522BDCD3e392B59;
    address public LIQ = 0x2881c5dF65A8D81e38f7636122aFb456514804CC; // MIP21-LIQ-ORACLE

    // changelog IDs
    bytes32 public constant dropID = "RWA004";
    bytes32 public constant joinID = "MCD_JOIN_RWA004_A";
    bytes32 public constant urnID = "RWA004_A_URN";
    bytes32 public constant inputConduitID = "RWA004_A_INPUT_CONDUIT";
    bytes32 public constant outputConduitID = "RWA004_A_OUTPUT_CONDUIT";
    bytes32 public constant pipID = "PIP_RWA004";

    // values, based on https://forum.makerdao.com/t/htc-drop-collateral-onboarding-risk-evaluation/8001
    bytes32 public constant ilk = "RWA004-A";
    // look up in https://ipfs.io/ipfs/QmefQMseb3AiTapiAKKexdKHig8wroKuZbmLtPLv4u2YwW
    uint256 public constant RATE = 1000000002145441671308778766; // 7% stability fee
    uint256 public constant DC = 7 * MILLION * RAD; // creditline: 7 mio
    uint256 public constant MAT = 110 * RAY / 100   ; // Min Vault CR of 110%
    uint256 public constant INITIAL_PRICE =  8_014_300 * WAD; // creditLine + 2 years of stability fee => 7000000 * 1.07^2
}
