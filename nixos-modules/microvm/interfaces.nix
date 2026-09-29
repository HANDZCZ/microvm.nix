mkShortId: { config, lib, pkgs, ... }:

let
  interfacesByType = wantedType:
    builtins.filter ({ type, ... }: type == wantedType)
      config.microvm.interfaces;

  tapInterfaces = interfacesByType "tap";
  macvtapInterfaces = interfacesByType "macvtap";

  tapFlags = lib.concatStringsSep " " (
    [ "vnet_hdr" ] ++
    lib.optional config.microvm.declaredRunner.passthru.tapMultiQueue "multi_queue"
  );

  mkAltnameCmd = id: altName: "${lib.getExe' pkgs.iproute2 "ip"} link property add dev '${id}' altname '${altName}'";

  # TODO: don't hardcode but obtain from host config
  user = "microvm";
  group = "kvm";
in
{
  microvm.binScripts = lib.mkMerge [ (
    lib.mkIf (tapInterfaces != []) {
      tap-up = ''
        set -eou pipefail
      '' + lib.concatMapStrings ({ id, ... }: let
        shortId = mkShortId id;
      in ''
        if [ -e /sys/class/net/${shortId} ]; then
          ${lib.getExe' pkgs.iproute2 "ip"} link delete '${shortId}'
        fi

        ${lib.getExe' pkgs.iproute2 "ip"} tuntap add name '${shortId}' mode tap user '${user}' ${tapFlags}
        ${mkAltnameCmd shortId id}
        ${lib.getExe' pkgs.iproute2 "ip"} link set '${shortId}' up
      '') tapInterfaces;

      tap-down = ''
        set -ou pipefail
      '' + lib.concatMapStrings ({ id, ... }: let
        shortId = mkShortId id;
      in ''
        ${lib.getExe' pkgs.iproute2 "ip"} link delete '${shortId}'
      '') tapInterfaces;
    }
  ) (
    lib.mkIf (macvtapInterfaces != []) {
      macvtap-up = ''
        set -eou pipefail
      '' + lib.concatMapStrings ({ id, mac, macvtap, ... }: let
        shortId = mkShortId id;
      in ''
        if [ -e /sys/class/net/${shortId} ]; then
          ${lib.getExe' pkgs.iproute2 "ip"} link delete '${shortId}'
        fi
        ${lib.getExe' pkgs.iproute2 "ip"} link add link '${macvtap.link}' name '${shortId}' address '${mac}' type macvtap mode '${macvtap.mode}'
        ${lib.getExe' pkgs.iproute2 "ip"} link set '${shortId}' allmulticast on
        if [ -f "/proc/sys/net/ipv6/conf/${shortId}/disable_ipv6" ]; then
          echo 1 > "/proc/sys/net/ipv6/conf/${shortId}/disable_ipv6"
        fi
        ${mkAltnameCmd shortId id}
        ${lib.getExe' pkgs.iproute2 "ip"} link set '${shortId}' up
        ${pkgs.coreutils-full}/bin/chown '${user}:${group}' /dev/tap$(< "/sys/class/net/${shortId}/ifindex")
      '') macvtapInterfaces;

      macvtap-down = ''
        set -ou pipefail
      '' + lib.concatMapStrings ({ id, ... }: let
        shortId = mkShortId id;
      in ''
        ${lib.getExe' pkgs.iproute2 "ip"} link delete '${shortId}'
      '') macvtapInterfaces;
    }
  ) ];
}
