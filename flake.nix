# Hermes Terminal - SSH-accessible container for Hermes Agent
#
# This flake builds an OCI container image that serves as a terminal host
# for the Hermes Agent, providing SSH access and a configurable set of
# development tools.
#
# Build the container:
#   nix build .#container
#
# Push to registry:
#   nix run .#push
#
# Push with specific tag:
#   nix build .#push-v1 && ./result/bin/deployContainers

{
  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    utils.url = "github:numtide/flake-utils";

    fudo-nix-helpers = {
      url = "path:/net/projects/niten/nix-helpers";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, utils, fudo-nix-helpers, ... }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };

        helpers = fudo-nix-helpers.legacyPackages.${system};

        # --------------------------------------------------------------------
        # Configuration - Customize these for your environment
        # --------------------------------------------------------------------

        # Container registry settings
        containerConfig = {
          name = "hermes-terminal";
          repo = "registry.kube.sea.fudo.link";
          tag = "latest";
        };

        # SSH authorized keys for the Hermes agent
        # Note: In Kubernetes, keys are managed via the hermes-terminal-ssh-keys secret.
        # These keys are baked into the image as a fallback for non-K8s usage.
        authorizedKeys = [
          "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBMBsJi3nN8/9Zy2LKYOeSHzKaPTVL+mA9sgxoiB5Hf1i7OxVY81ZUy9VCo8eiZZ31+fX67xank4QxQslmD5wUOQ="
        ];

        # Additional packages to include in the terminal
        # These are the tools Hermes will have access to
        terminalPackages = with pkgs; [
          # Programming languages
          clang
          cmake
          gcc
          python3
          make
          nodejs
          npm

          # Build tools
          gnumake
          cmake
          nix

          # System
          btop
          htop
          flux
          iproute2
          kubectl
          netstat
          ss
          tmux

          # Version control (git is included by default)
          gh # GitHub CLI

          # Text processing
          fd
          jless
          jq
          yq-go
          ripgrep
          fd
          yq

          # Network tools
          curl
          netcat
          net-tools
          openssh
          wget

          # Secrets
          age
          sops
          vault

          # Development utilities
          tree
          tmux
          vim
          nano
        ];

        # Environment variables for the container
        containerEnv = {
          EDITOR = "vim";
          TERM = "xterm-256color";
        };

        # --------------------------------------------------------------------
        # Container definitions
        # --------------------------------------------------------------------

        # The main terminal container
        terminalContainer = helpers.makeTerminalContainer {
          inherit (containerConfig) name repo tag;
          inherit authorizedKeys;

          user = "hermes";
          packages = terminalPackages;
          env = containerEnv;

          # Git is enabled by default
          enableGit = true;

          # Enable nix if you want the agent to be able to install packages
          enableNix = false;

          # Additional sshd configuration if needed
          extraSshdConfig = ''
            # Allow agent forwarding for git operations
            AllowAgentForwarding yes
            # Disable PAM account checks - hermes account has no password (locked),
            # which causes PAM to reject logins even with valid SSH keys.
            UsePAM no
          '';
        };

        # Deploy script for pushing to registry
        deployContainer = helpers.deployTerminalContainer {
          inherit (containerConfig) name repo;
          inherit authorizedKeys;
          user = "hermes";
          packages = terminalPackages;
          env = containerEnv;
          enableGit = true;
          enableNix = false;
          extraSshdConfig = ''
            AllowAgentForwarding yes
          '';

          tags = [ "latest" ];
          verbose = true;
        };

        # Versioned deploy (example: for releases)
        deployContainerVersioned = helpers.deployTerminalContainer {
          inherit (containerConfig) name repo;
          inherit authorizedKeys;
          user = "hermes";
          packages = terminalPackages;
          env = containerEnv;
          enableGit = true;
          enableNix = false;

          tags = [ "v1.0.0" "latest" ];
          verbose = true;
        };

      in {
        packages = {
          # The container image itself
          container = terminalContainer;
          default = terminalContainer;

          # Push scripts
          push = deployContainer;
          push-versioned = deployContainerVersioned;
        };

        # Development shell for working on this configuration
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            skopeo # For pushing containers
            dive # For inspecting container layers
          ];
        };
      });
}
