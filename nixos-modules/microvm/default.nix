{ config, lib, pkgs, ... }:

let
  microvm-lib = import ../../lib {
    inherit lib;
  };

  mkShortId = id: lib.pipe id [
    (val: lib.hashString "sha256" "microvm.nix:${val}")
    (lib.substring 0 12)
    (val: "mv-${val}")
  ];
in

{
  imports = [
    ./boot-disk.nix
    ./store-disk.nix
    ./options.nix
    ./asserts.nix
    ./system.nix
    ./mounts.nix
    (import ./interfaces.nix mkShortId)
    ./pci-devices.nix
    ./virtiofsd
    ./graphics.nix
    ./rosetta.nix
    ./optimization.nix
    ./ssh-deploy.nix
    ./vsock-ssh.nix
  ];

  config = {
    microvm.runner = lib.genAttrs microvm-lib.hypervisors (hypervisor:
      microvm-lib.buildRunner {
        inherit pkgs;
        microvmConfig = config.microvm
        // {
          interfaces = lib.map (val:
            if lib.elem val.type [ "tap" "macvtap" ]
              then val // { id = mkShortId val.id; }
              else val
          ) config.microvm.interfaces;
        }
        // {
          inherit (config.networking) hostName;
          inherit hypervisor;
        };
        inherit (config.system.build) toplevel;
      }
    );
  };
}
