{
  fetchFromGitHub,
  fetchNpmDeps,
  fetchurl,
  pi-coding-agent,
}:

let
  version = "0.84.4";
  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    tag = "v${version}";
    hash = "sha256-7z8OXao1PzmBEepDkIqVqyfQBPHulBlKcGymDYsnMvc=";
  };
  modelData = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${version}.tgz";
    hash = "sha512-AClAZxf5+c4RRu44NJPS6wyQy+Nmq+Mzyyrdvm4ZVMNuixelO02RZX4G4Aq1F145Yzp43wnM5S+hLlSI7ypfVw==";
  };
in
pi-coding-agent.overrideAttrs (_previous: {
  inherit version src modelData;

  npmDeps = fetchNpmDeps {
    inherit src;
    hash = "sha256-35GC3Q4Jf4URvqoEYHeM63x49tTmrth62//PvKm4I7Q=";
  };

  # Kept in sync with npmDeps for nixpkgs' npm config hook diagnostics.
  npmDepsHash = "sha256-35GC3Q4Jf4URvqoEYHeM63x49tTmrth62//PvKm4I7Q=";

  # The upstream model-data generator requires network access. Hydrate the
  # matching published pi-ai data exactly as the nixpkgs derivation does.
  preConfigure = ''
    mkdir -p packages/ai/src/providers/data
    tar --extract --gzip --file=${modelData} \
      --directory=packages/ai/src/providers/data \
      --strip-components=4 \
      package/dist/providers/data
  '';
})
