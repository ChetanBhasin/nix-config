{
  fetchFromGitHub,
  fetchNpmDeps,
  fetchurl,
  pi-coding-agent,
}:

let
  version = "0.84.3";
  src = fetchFromGitHub {
    owner = "earendil-works";
    repo = "pi";
    tag = "v${version}";
    hash = "sha256-fC9pKgP2qD61ae5d7iOqP8anl88J1N1Bq8X8+aAjA2A=";
  };
  modelData = fetchurl {
    url = "https://registry.npmjs.org/@earendil-works/pi-ai/-/pi-ai-${version}.tgz";
    hash = "sha512-M0YUV8vNO3y2WwWSyY8ijKJV5W4gkSUixuvk+Z00ZBjsyMfsdXfITsHEwP1UIf09YRWXT6oGn0GlCamt+P32XQ==";
  };
in
pi-coding-agent.overrideAttrs (_previous: {
  inherit version src modelData;

  npmDeps = fetchNpmDeps {
    inherit src;
    hash = "sha256-cDx28+c4bwtQpiy5+BCvZhZezoZb4WRqfZj2eoEeMbw=";
  };

  # Kept in sync with npmDeps for nixpkgs' npm config hook diagnostics.
  npmDepsHash = "sha256-cDx28+c4bwtQpiy5+BCvZhZezoZb4WRqfZj2eoEeMbw=";

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
