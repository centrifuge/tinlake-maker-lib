let
  pkgs = import (builtins.fetchGit rec {
    name = "dapptools-${rev}";
    url = https://github.com/dapphub/dapptools;
    rev = "e855b6544270769fe00987fe0265cc1af6bf47a6";
  }) {};

in
  pkgs.mkShell {
    src = null;
    name = "tinlake-maker-lib";
    buildInputs = with pkgs; [
      pkgs.dapp
      pkgs.solc-versions.solc_0_5_15
    ];
  }
