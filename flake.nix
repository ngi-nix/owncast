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
        owncast = buildGoModule {
          pname = "owncast";
          version = "dirty"; #self.shortRev or "${nixpkgs.lib.substring 0 8 self.lastModifiedDate}-dev"; # "x.x.x" for releases

          propagatedBuildInputs = [ ffmpeg ];

          nativeBuildInputs = [ makeWrapper ];

          src = ./.;

          vendorSha256 = "sha256-jx2dJbG8ebjGkyE5D3jUHkmw/nfjeqM38iwmO+7i6oA=";

          postInstall = ''
            wrapProgram $out/bin/owncast --prefix PATH : ${
              lib.makeBinPath [ bash ffmpeg which ]
            }
          '';

          meta = {
            homepage = "https://owncast.online";
            description = ''
              Owncast is a self-hosted live video and web chat server for use
              with existing popular broadcasting software
            '';
            license = lib.licenses.mit;
            platforms = lib.platforms.unix;
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
        let cfg = config.services.owncast;
        in
        with lib;
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
                  client.succeed("echo 'Test Pass!'")
                '';
            };
        });
    };
}
