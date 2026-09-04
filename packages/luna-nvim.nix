# luna.nvim — upstream Neovim integrations and semantic accent palette.
# The local on_colors hook in home/neovim softens its neutral surface ladder
# to match this repo's Luna Comfort palette in modules/theme/luna.nix.
{
  lib,
  vimUtils,
  fetchFromGitHub,
}:

vimUtils.buildVimPlugin {
  pname = "luna-nvim";
  # Upstream has no tagged releases; pin by commit and bump when needed.
  version = "2026-08-25";

  src = fetchFromGitHub {
    owner = "WTFox";
    repo = "luna.nvim";
    rev = "727c19334528e1b8939f518d1ea43c4e62d98f91";
    hash = "sha256-3c/UhbK9UYvcpYRQuhwPXzOk1G1tpBnx7rUWoq4LPFE=";
  };

  meta = with lib; {
    description = "A near-black Neovim colorscheme built on greys with four accent hues";
    homepage = "https://github.com/WTFox/luna.nvim";
    license = licenses.mit;
  };
}
