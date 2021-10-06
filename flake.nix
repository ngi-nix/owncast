{
  description = "Owncast";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "i686-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];

      forAllSystems = f:
        nixpkgs.lib.genAttrs supportedSystems (system: f system);

      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
        });
    in
    {
      overlay = final: prev: with prev; {
        owncast = buildGoModule rec {
          pname = "owncast";
          version = self.shortRev or "${nixpkgs.lib.substring 0 8 self.lastModifiedDate}-dev"; # "x.x.x" for releases

          src = ./.;

          vendorSha256 = "sha256-NARHYeOVT7sxfL1BdJc/CPCgHNZzjWE7kACJvrEC71Y=";

          propagatedBuildInputs = [ ffmpeg ];

          buildInputs = [ makeWrapper ];

          preInstall = ''
            mkdir -p $out
            cp -r $src/{static,webroot} $out
          '';

          postInstall =
            let
              setupScript = ''
                [ ! -d $PWD/static ] && ln -s ${placeholder "out"}/static $PWD
                [ ! -d $PWD/webroot ] && cp --no-preserve=mode -r ${placeholder "out"}/webroot $PWD
              '';
            in
            ''
              wrapProgram $out/bin/owncast \
                --run '${setupScript}' \
                --prefix PATH : ${lib.makeBinPath [ bash which ffmpeg ]}
            '';

          installCheckPhase = ''
            runHook preCheck
            $out/bin/owncast --help
            runHook postCheck
          '';

          meta = with lib; {
            description = "self-hosted video live streaming solution";
            homepage = "https://owncast.online";
            license = licenses.mit;
            platforms = platforms.unix;
          };
        };
      };

      packages = forAllSystems (system: {
        inherit (nixpkgsFor.${system}) owncast;
      });

      defaultPackage = forAllSystems (system:
        self.packages.${system}.owncast);

      devShell = self.defaultPackage;
    };
}
