let
  pkgs = import (builtins.fetchGit rec {
    name = "dapptools-${rev}";
    url = https://github.com/dapphub/dapptools;
    rev = "9cc836c2d56d5ff2fd800f838cb172fd47e5622d";
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
