{
  description = "Dev shell for testing the Home Assistant blueprints";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
    in
    {
      devShells = nixpkgs.lib.genAttrs systems (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          python = pkgs.python314;
        in
        {
          default = pkgs.mkShellNoCC {
            packages = [
              pkgs.uv
              python
            ];
            # Run test scripts on the pinned Python instead of letting uv download one.
            env = {
              UV_PYTHON = "${python}/bin/python3";
              UV_PYTHON_DOWNLOADS = "never";
            };
          };
        }
      );
    };
}
