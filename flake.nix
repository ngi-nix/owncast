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
          version = "dirty";

          src = ./.;

          vendorSha256 = "sha256-jx2dJbG8ebjGkyE5D3jUHkmw/nfjeqM38iwmO+7i6oA=";

          propagatedBuildInputs = [ ffmpeg ];

          buildInputs = [ makeWrapper ];

          preInstall = ''
            mkdir -p $out
            cp -r $src/{static,webroot} $out
          '';

          postInstall =
            let
              setupScript = ''
                ([ ! -d $PWD/static ] && [ ! -d $PWD/webroot} ]) && (
                  cp -r ${placeholder "out"}/webroot $PWD/webroot
                  ln -s ${placeholder "out"}/static $PWD/static
                  chmod -R u+w $PWD/webroot
                )
              '';
            in
            ''
              wrapProgram $out/bin/owncast \
                --run '${setupScript}' \
                --prefix PATH : ${
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
                description = ''
                  The directory where owncast stores its data files.
                '';
              };

              openFirewall = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Open the appropriate ports in the firewall for owncast.
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
                default = "127.0.0.1";
                example = "0.0.0.0";
                description = "The IP address to bind the owncast server to.";
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

              systemd.services.owncast = {
                description = "A self-hosted live video and web chat server";
                wantedBy = [ "default.target" ];

                serviceConfig = {
                  User = cfg.user;
                  Group = cfg.group;
                  WorkingDirectory = cfg.dataDir;
                  ExecStart = "${pkgs.owncast}/bin/owncast -webserverport ${toString cfg.port} -rtmpport ${toString cfg.rtmp-port} -webserverip ${cfg.listen}";
                  Restart = "on-failure";
                  StateDirectory = cfg.dataDir;
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

              users.groups = mkIf (cfg.group == "owncast") { owncast = { }; };

              networking.firewall =
                mkIf cfg.openFirewall { allowedTCPPorts = [ cfg.rtmp-port ] ++ optional (cfg.listen != "127.0.0.1") cfg.port; };

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
                  environment.systemPackages = [ curl ];
                  nixpkgs.overlays = [ self.overlay ];
                  services.owncast = {
                    enable = true;
                    port = 8080;
                  };
                };
              };

              testScript =
                ''
                  start_all()
                  client.wait_for_unit("owncast.service")
                  client.succeed("curl localhost:8080/api/status")
                '';
            };
        });
    };
}
