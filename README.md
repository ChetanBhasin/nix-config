# Chetan's Nix Configuration

This repository includes the configuration for the commonly used systems that I use including my personal laptop and a couple of other devices.

## Installation Instructions

The idea is to be able to install the entire system configuration from one place. Please follow the given instructions for setting up the system and note that you need to perform certain steps for MacOS.

### Installing MacOS Dependencies

The first thing we need to do is install the command line tools for MacOS. These include basic configuration that Mac does not include.

```bash
xcode-select --install
```

Now we will install Homebrew, which is used for many packages that aren't available on Nix for MacOS.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### Installing Nix (MacOS/Linux/ not tested for WSL but could work)

Since we're using Nix to manage everything, we need to install Nix itself. I recommend NOT using the official installer and using the one from provided [here](https://github.com/DeterminateSystems/nix-installer). The following command will install it for you:

```bash
curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install
```


### Installing Profile (MacOS/Linux, not tested for WSL but could work)

Clone this repository and you can use `make` to install a profile. Just pick a host that you would like to install and Nix will do the rest. For example, to install the `hugh` _profile_, you could run the following command.

```bash
make apply-darwin host=hugh
```

Hugh is configured for Darwin (i.e., MacOS). The above given `make` target will work on MacOS systems. For a NixOS system like `bill`, one could run:

```bash
make apply-nix host=bill
```

# Credits

Thanks for [Frank](https://github.com/fmoda3/nix-configs) for sharing his Nix configuration, from which I learned a lot.