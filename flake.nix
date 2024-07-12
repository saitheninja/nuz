{
  description = "Zig 0.13.0 development environment";
  # `nix develop -c $SHELL` otherwise it defaults to bash

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/655a58a72a6601292512670343087c2d75d859c1";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

    in
    {
      devShells.${system}.default = pkgs.mkShell {
        # build tools
        # executed at build time, on buildPlatform
        nativeBuildInputs = with pkgs; [ zig ];

        # dependencies
        # executed at run time, on hostPlatform
        #buildInputs = [ ];

        # `packages` is just combined with `nativeBuildInputs`
        # https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/mkshell/default.nix#L41

        # AN_ENVIRONMENT_VARIABLE = "something";

        # execute when entering the shell environment with `nix develop`
        shellHook = ''
          zig version
        '';
      };
    };
}
