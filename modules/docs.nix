{ pkgs, ... }:

let
  docsPath = "/etc/safe-live/docs";

  safeDocs = pkgs.writeShellApplication {
    name = "safe-docs";
    runtimeInputs = with pkgs; [ glow ];
    text = ''
      set -euo pipefail

      if [ ! -d "${docsPath}" ]; then
        echo "ERROR: docs not found at ${docsPath}" >&2
        exit 1
      fi

      # Opens glow's TUI browser on the docs directory.
      # Navigate with arrow keys, Enter to read, Esc/q to go back.
      exec glow "${docsPath}"
    '';
  };

  docsDesktop = pkgs.makeDesktopItem {
    name = "safe-live-docs";
    desktopName = "Safe Live Docs (Terminal)";
    genericName = "Safe Live Documentation";
    comment = "Open local Markdown guides in glow TUI browser";
    exec = "/run/current-system/sw/bin/foot -e /run/current-system/sw/bin/safe-docs";
    icon = "accessories-dictionary";
    terminal = false;
    categories = [ "Documentation" "Utility" ];
  };

  docsGuiDesktop = pkgs.makeDesktopItem {
    name = "safe-live-docs-gui";
    desktopName = "Safe Live Docs (GUI)";
    genericName = "Safe Live Documentation";
    comment = "Open local Markdown guides in Ghostwriter";
    exec = "/run/current-system/sw/bin/ghostwriter ${docsPath}/README.md";
    icon = "accessories-text-editor";
    terminal = false;
    categories = [ "Documentation" "Utility" ];
    extraConfig = {
      Path = docsPath;
    };
  };

in
{
  environment.etc."safe-live/docs".source = ../image/docs;
  environment.etc."safe-live/scripts".source = ../image/scripts;

  environment.systemPackages = with pkgs; [
    glow
    less
    kdePackages.ghostwriter
    safeDocs
    docsDesktop
    docsGuiDesktop
  ];
}
