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
          version = self.shortRev or "${nixpkgs.lib.substring 0 8 self.lastModifiedDate}-dev"; # "x.x.x" for releases

          buildInputs = [ ffmpeg ];

          src = ./.;

          vendorSha256 = "sha256-jx2dJbG8ebjGkyE5D3jUHkmw/nfjeqM38iwmO+7i6oA=";

          meta = {
            homepage = "https://owncast.online";
            description = ''
              Owncast is a self-hosted live video and web chat server for use
              with existing popular broadcasting software
            '';
            license = lib.licenses.mit;
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
        with nixpkgs.lib;
        { config, pkgs, ... }:
        let
          cfg = config.services.owncast;
        in
        {
          options = {
            services.owncast = {
              enable = mkEnableOption "Jellyfin Media Server";

              package = mkOption {
                type = types.package;
                default = pkgs.owncast;
                example = literalExample "pkgs.owncast";
                description = ''
                  Owncast package to use.
                '';
              };

              openFirewall = mkOption {
                type = types.bool;
                default = false;
                description = ''
                  Open the default ports in the firewall for the server. The
                  HTTP/HTTPS ports can be changed in the Web UI, so this option should
                  only be used if they are unchanged.
                '';
              };

              httpPort = mkOption {
                type = types.int;
                default = 8080;
                description = ''
                  HTTP Port to use.
                '';
              };

              rtmpPort = mkOption {
                type = types.int;
                default = 1935;
                description = ''
                  RTMP Port to use.
                '';
              };

              streamkey = mkOption {
                type = types.string;
                default = "abc123";
                description = ''
                  Stream key to use.
                '';
              };
            };
          };

          config = mkIf cfg.enable {
            systemd.services.owncast = {
              description = "Owncast Server";
              after = [ "network.target" ];
              wantedBy = [ "multi-user.target" ];

              serviceConfig = rec {
                User = cfg.user;
                Group = cfg.group;
                ExecStart = "${cfg.package}/bin/owncast -webserverport ${toString cfg.httpPort} -rtmpport ${toString cfg.rtmpPort} -database /var/lib/owncast/db -streamkey ${cfg.streamkey}";
                Restart = "on-failure";

                # Security options:

                NoNewPrivileges = true;

                AmbientCapabilities = "";
                CapabilityBoundingSet = "";

                # ProtectClock= adds DeviceAllow=char-rtc r
                DeviceAllow = "";

                LockPersonality = true;

                PrivateTmp = true;
                PrivateDevices = true;
                PrivateUsers = true;

                ProtectClock = true;
                ProtectControlGroups = true;
                ProtectHostname = true;
                ProtectKernelLogs = true;
                ProtectKernelModules = true;
                ProtectKernelTunables = true;

                RemoveIPC = true;

                RestrictNamespaces = true;
              };
            };

            networking.firewall = mkIf cfg.openFirewall {
              allowedTCPPorts = with cfg; [ rtmpPort httpPort ];
            };
          };
        };

      nixosModule = self.nixosModules.owncast;
    };
}
