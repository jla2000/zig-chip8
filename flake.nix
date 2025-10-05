{
  inputs.nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

  outputs = inputs:
    let
      system = "x86_64-linux";
      pkgs = inputs.nixpkgs.legacyPackages.${system};
    in
    {
      packages.${system}.default = pkgs.stdenv.mkDerivation {
        name = "zig-chip8";
        src = pkgs.lib.cleanSource ./.;
        buildInputs = [ pkgs.raylib ];
        nativeBuildInputs = [ pkgs.zig ];

        # zig.hook broken:
        # https://github.com/NixOS/nixpkgs/issues/247719
        installPhase = ''
          mkdir -p $out
          zig build -p $out --global-cache-dir .
        '';
      };

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [ pkgs.raylib ];
        nativeBuildInputs = [ pkgs.zig ];
      };
    };
}
