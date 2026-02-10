{ pkgs, ...}:

{
  home.username = "garaemon";
  home.homeDirectory = "/Users/garaemon";

  home.stateVersion = "25.05";
  home.packages = [pkgs.jq];

  home.file.".gitignore".source = ./roles/git/tasks/files/gitignore;

  programs.home-manager.enable = true;
}
