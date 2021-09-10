{
  description = "Owncast";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "aarch64-linux" "i686-linux" "x86_64-linux" ];

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
          version = "0.0.8";

          src = fetchFromGitHub {
            owner = "owncast";
            repo = "owncast";
            rev = "v${version}";
            sha256 = "0md4iafa767yxkwh6z8zpcjv9zd79ql2wapx9vzyd973ksvrdaw2";
          };

          vendorSha256 = "sha256-bH2CWIgpOS974/P98n0R9ebGTJ0YoqPlH8UmxSYNHeM=";

          propagatedBuildInputs = [ ffmpeg ];

          buildInputs = [ makeWrapper ];

          postInstall = ''
            wrapProgram $out/bin/owncast --prefix PATH : ${
              lib.makeBinPath [ bash which ffmpeg ]
            }
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
            maintainers = with maintainers; [ mayniklas ];
          };
        };
      };

      packages = forAllSystems (system: {
        inherit (nixpkgsFor.${system}) owncast;
      });

      defaultPackage = forAllSystems (system:
        self.packages.${system}.owncast);

      devShell = self.defaultPackage;

      nixosModules.owncast =
        { lib, pkgs, config, ... }:
          with lib;
          let cfg = config.services.owncast;
          in
          {

            options.services.owncast = {

              enable = mkEnableOption "owncast";

              dataDir = mkOption {
                type = types.str;
                default = "/var/lib/owncast";
                description = "The directory where owncast stores its data files.";
              };

              openFirewall = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Open ports in the firewall for owncast.
                '';
              };

              user = mkOption {
                type = types.str;
                default = "owncast";
                description = "User account under which owncast runs.";
              };

              group = mkOption {
                type = types.str;
                default = "owncast";
                description = "Group under which owncast runs.";
              };

              listen = mkOption {
                type = types.str;
                default = "0.0.0.0";
                example = "127.0.0.1";
                description = "The IP address to bind owncast to.";
              };

              port = mkOption {
                type = types.port;
                default = 80;
                description = ''
                  TCP port where owncast web-gui listens.
                '';
              };

              rtmp-port = mkOption {
                type = types.port;
                default = 1935;
                description = ''
                  TCP port where owncast rtmp service listens.
                '';
              };

            };

            config = mkIf cfg.enable {

              systemd.tmpfiles.rules = [
                "L+ '${cfg.dataDir}/static' - - - - ${pkgs.owncast.src}/static"
                "C '${cfg.dataDir}/webroot' 0700 - - - ${pkgs.owncast.src}/webroot"
              ];

              systemd.services.owncast = {
                wantedBy = [ "default.target" ];

                serviceConfig = {
                  User = cfg.user;
                  Group = cfg.group;
                  WorkingDirectory = cfg.dataDir;
                  StateDirectory = baseNameOf cfg.dataDir;
                  ExecStart = "${pkgs.owncast}/bin/owncast -webserverport ${toString cfg.port} -rtmpport ${toString cfg.rtmp-port} -webserverip ${cfg.listen}";
                  Restart = "on-failure";
                };

                environment = {
                  LC_ALL = "en_US.UTF-8";
                  LANG = "en_US.UTF-8";
                };
              };

              users.users = mkIf (cfg.user == "owncast") {
                owncast = {
                  isSystemUser = true;
                  group = cfg.group;
                  description = "owncast system user";
                };
              };

              users.groups = mkIf (cfg.group == "owncast") { ${cfg.group} = { }; };

              networking.firewall =
                mkIf cfg.openFirewall { allowedTCPPorts = [ cfg.port cfg.rtmp-port ]; };

            };
            meta = { maintainers = with lib.maintainers; [ mayniklas ]; };
          };

      nixosModule = self.nixosModules.owncast;

      checks = forAllSystems (system:
        with nixpkgsFor.${system};
        {
          inherit (self.packages.${system}) owncast;

          # A VM test of the NixOS module.
          vmTest =
            with import (nixpkgs + "/nixos/lib/testing-python.nix") { inherit system; };

            makeTest {
              nodes = {
                client = { ... }: {
                  imports = [ self.nixosModules.owncast ];
                  nixpkgs.overlays = [ self.overlay ];
                  services.owncast.enable = true;
                };
              };

              testScript =
                ''
                  start_all()
                  client.wait_for_unit("owncast.service")
                  client.succeed("${curl}/bin/curl 127.0.0.1/api/status")
                '';
            };
        });
    };
}
