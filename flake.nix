{
  description = "Multiple dev environments";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { nixpkgs, flake-utils, ... }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          name = "rust";
          buildInputs = with pkgs; [
            rustc
            cargo
            rust-analyzer
            clippy
            pkg-config
            # runtime deps
            imagemagick # required by image.nvim
            mpv # playback
            yt-dlp # search fallback + mpv stream resolver
          ];
          shellHook = ''
            export PROMPT_SUFFIX="(nix)"
            export SHELL=/run/current-system/sw/bin/zsh
          '';
        };
      }
    );
}
