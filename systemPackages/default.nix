{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Shared system packages available across all platforms (Darwin and Linux)
  environment.systemPackages =
    with pkgs;
    [
      # Development Build Tools
      autoconf
      automake
      libtool
      pkg-config
      cmake
      gnumake
    ]
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [ gcc ]
    ++ [
      openssl
      iconv
      libiconv
      libpq

      # Container and Infrastructure Tools
      docker
      docker-buildx
      docker-compose
      kubectl
      kubectx
      kubernetes-helm
      helmfile
      argocd
      terraform
      opentofu
      just
      doppler
      tea

      # Development Languages and Runtimes
      bun
      uv
      python313
      rustup
      go
      nodejs

      # Database and API Tools
      amazon-ecr-credential-helper
      rdkafka
      protobuf
      protox
      grpc
      postgresql
      redis
      httpie

      # Security and Network Tools
      curl
      wget
      nmap

      # File and Archive Tools
      zip
      unzip
      gnutar

      claude-code
      codex
      opencode

      # Git and Version Control
      git
      git-lfs

      # System Monitoring and Process Management
      htop
      tree

      # Text Processing and Utilities
      jq
      yq

      # Image Processing
      leptonica
      tesseract
      poppler

      # Development IDE Support
      nil # Nix LSP
    ];
}
