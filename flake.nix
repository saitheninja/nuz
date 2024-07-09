{
  description = "Zig 0.13.0 development environment";
  # `nix develop -c $SHELL` otherwise it defaults to bash

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/655a58a72a6601292512670343087c2d75d859c1";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

    in {
      devShells.${system}.default = pkgs.mkShell { 
        packages = with pkgs; [ 
          zig
        ]; 

        shellHook = ''
          zig version
        '';
      };
    };
}
