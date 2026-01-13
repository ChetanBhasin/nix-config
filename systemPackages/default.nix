{ config, pkgs, lib, ... }: {
  # Shared system packages available across all platforms (Darwin and Linux)
  environment.systemPackages = with pkgs;
    [
      # Development Build Tools
      autoconf
      automake
      libtool
      pkg-config
      cmake
      gnumake
    ]
    ++ lib.optionals pkgs.stdenv.isLinux [ gcc ]
    ++ lib.optionals (llvmPackages ? libcxx) [ llvmPackages.libcxx ]
    ++ lib.optionals (llvmPackages ? libcxxabi) [ llvmPackages.libcxxabi ]
    ++ [
      openssl
    iconv
    libiconv
    libpq

    # Container and Infrastructure Tools
    docker
    docker-compose
    kubectl
    kubectx
    kubernetes-helm
    helmfile
    argocd
    terraform
    opentofu
    mise
    just
    doppler
    tea

    # Development Languages and Runtimes
    bun
    uv
    deno
    python3
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
