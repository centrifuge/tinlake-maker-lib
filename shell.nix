let
  pkgs = import (builtins.fetchGit rec {
    name = "dapptools-${rev}";
    url = https://github.com/dapphub/dapptools;
    rev = "dc992eb2e9d05bee150156add790bddb160fc80c";
  }) {};

in
  pkgs.mkShell {
    src = null;
    name = "tinlake-maker-lib";
    buildInputs = with pkgs; [
      pkgs.dapp
      pkgs.solc-static-versions.solc_0_5_15
    ];
  }
