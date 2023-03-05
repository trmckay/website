{
  description = "tmckay.dev";
  inputs.flake-utils.url = "github:numtide/flake-utils";
  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
        rec {
          devShell = pkgs.mkShell { buildInputs = with pkgs; [ hugo ]; };
          nixosConfigurations."${config.networking.hostName}" = {
            services.caddy = {
              enable = true;
            };
          };
        }
    );
}
