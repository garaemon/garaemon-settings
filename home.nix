{ pkgs, username, email, homeDirectory, ...}:

{
  home.username = username;
  home.homeDirectory = homeDirectory;

  home.stateVersion = "25.05";
  home.packages = [
    pkgs.ghq
  ];

  home.file.".gitignore".source = ./resources/gitignore;

  programs.git = {
    enable = true;
    userName = "Ryohei Ueda";
    userEmail = email;
    lfs.enable = true;
    delta = {
      enable = true;
      options = {
        navigate = true;
        side-by-side = true;
      };
    };
    aliases = {
      see = "browse";
      p = "pull-request";
      br = "branch";
      co = "checkout";
      st = "status";
      unstage = "reset -q HEAD --";
      uncommit = "reset --mixed HEAD~";
      graph = "log --graph -10 --branches --remotes --tags --format=format:'%Cgreen%h %Creset• %<(75,trunc)%s (%cN, %cr) %Cred%d' --date-order";
      precommit = "diff --cached --diff-algorithm=minimal -w";
      unmerged = "diff --name-only --diff-filter=U";
      remotes = "remote -v";
    };
    extraConfig = {
      merge = {
        conflictStyle = "zdiff3";
      };
      rebase = {
        autostash = true;
      };
      init = {
        defaultBranch = "main";
      };
      core = {
        excludesFile = "~/.gitignore";
      };
    };
  };

  programs.gh = {
    enable = true;
    settings = {
      git_protocol = "ssh";
    };
  };

  nix = {
    package = pkgs.nix;
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
    };
  };

  programs.home-manager.enable = true;
}
