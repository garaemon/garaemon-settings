{
  description = "Home Manager configuration of Garaemon";

  inputs = {
    # Specify the source of Home Manager and Nixpkgs.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { nixpkgs, home-manager, ... }:
    let
      # Helper to create home-manager configurations for multiple platforms.
      mkHomeConfig = { username, email, homeDirectory, system, privateConfigPath ? ./private.nix }:
        let
          pkgs = nixpkgs.legacyPackages.${system};
        in
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;

          modules = [
            ./home.nix
            (if builtins.pathExists privateConfigPath then privateConfigPath else {})
          ];

          extraSpecialArgs = {
            inherit username email homeDirectory;
          };
        };
    in
    {
      homeConfigurations = {
        "garaemon@mac" = mkHomeConfig {
          username = "garaemon";
          email = "garaemon@gmail.com";
          homeDirectory = "/Users/garaemon";
          system = "aarch64-darwin";
        };
        "garaemon@linux-x86" = mkHomeConfig {
          username = "garaemon";
          email = "garaemon@gmail.com";
          homeDirectory = "/home/garaemon";
          system = "x86_64-linux";
        };
        "garaemon@linux-arm" = mkHomeConfig {
          username = "garaemon";
          email = "garaemon@gmail.com";
          homeDirectory = "/home/garaemon";
          system = "aarch64-linux";
        };
      };
    };
}
