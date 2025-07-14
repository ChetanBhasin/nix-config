{ config, pkgs, lib, ... }: {
  # Shared system packages available across all platforms (Darwin and Linux)
  environment.systemPackages = with pkgs; [
    # Development Build Tools
    autoconf
    automake
    libtool
    pkg-config
    cmake
    gnumake
    gcc
    openssl

    # Container and Infrastructure Tools
    docker
    docker-compose
    kubectl
    kubectx
    kubernetes-helm
    helmfile
    argocd
    terraform
    cloudflared

    # Development Languages and Runtimes
    bun
    uv
    deno
    python3Full
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
    mysql80
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

    # Git and Version Control
    git
    git-lfs

    # System Monitoring and Process Management
    htop
    tree

    # Text Processing and Utilities
    jq
    yq

    # Development IDE Support
    nil # Nix LSP
  ];
}
