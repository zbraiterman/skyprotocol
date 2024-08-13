# Example uses:
#   nix-shell --pure
#   nix-shell --arg precompile true
{ ethereum ? true, precompile ? false }:
let
  pkgs = import ./pkgs.nix;
  inherit (pkgs) lib skyprotocol gerbil-support gerbilPackages-unstable nixpkgs;
  inherit (gerbilPackages-unstable) gerbil-ethereum gerbil-poo;
  inherit (gerbil-support) gerbilLoadPath;
in
pkgs.mkShell {
  inputsFrom = [
    skyprotocol
  ];
  buildInputs = with pkgs; (
    skyprotocol.buildInputs ++
    lib.optional ethereum go-ethereum ++
    [ netcat ] # used by integration tests
    # TODO: Save at compile time
    # the path to the p2pd (go-libp2p-daemon) binary.
    # The path is useful because it is a hash -
    # so nix knows we depend on this exact version.
  );
  shellHook = ''
    echo ${gerbil-poo.src}; echo ${pkgs.gerbilPackages-unstable.gerbil-poo.src} ; echo
    echo ${skyprotocol.src}; echo ${pkgs.gerbilPackages-unstable.skyprotocol.src} ; echo ${pkgs.gerbilPackages-unstable.skyprotocol.src} ; echo ${pkgs.gerbil-support.gerbilPackages-unstable.skyprotocol.src} ; echo
    echo ${toString skyprotocol.passthru.pre-pkg.gerbilInputs}
    echo ${gerbil-poo}

    ${skyprotocol.postConfigure}
    export GERBIL_LOADPATH="${pkgs.testGerbilLoadPath}"
    PATH="${skyprotocol.out}/bin:$PATH"
    GERBIL_APPLICATION_HOME="$PWD"
    GERBIL_APPLICATION_SOURCE="$PWD"
    GLOW_HOME="$PWD"
    GLOW_SRC="$PWD"
  '';
}
