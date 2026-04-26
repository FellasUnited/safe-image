{ pkgs, lib, ... }:

{
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  security.polkit.enable = true;

  environment.sessionVariables = {
    XDG_CURRENT_DESKTOP = "sway";
    XDG_SESSION_TYPE = "wayland";
    # Dark theme for GTK3 apps and Firefox/LibreWolf.
    # GTK4/libadwaita apps (apostrophe) read the dconf color-scheme key instead.
    GTK_THEME = "Adwaita:dark";
  };

  # System-wide GTK3 dark mode (read via XDG_CONFIG_DIRS=/etc/xdg default).
  environment.etc."xdg/gtk-3.0/settings.ini".text = ''
    [Settings]
    gtk-application-prefer-dark-theme = true
    gtk-theme-name = Adwaita-dark
  '';

  # GTK4 dark mode fallback (libadwaita ignores this but it helps pure GTK4 apps).
  environment.etc."xdg/gtk-4.0/settings.ini".text = ''
    [Settings]
    gtk-application-prefer-dark-theme = true
  '';

  # dconf with system-level colour-scheme — the correct way to request dark mode
  # for libadwaita apps like apostrophe (GTK_THEME has no effect on them).
  programs.dconf = {
    enable = true;
    profiles.user.databases = [{
      settings = {
        "org/gnome/desktop/interface" = {
          color-scheme = "prefer-dark";
        };
      };
    }];
  };

  environment.etc."sway/config".text = ''
    # $mod = Win/Super key
    set $mod Mod4
    font pango:JetBrains Mono 10

    # Start notification daemon
    exec mako

    # Per-user SPICE vdagent client. Activates the system spice-vdagentd
    # socket and bridges clipboard to the host when QEMU exposes the
    # com.redhat.spice.0 virtio-serial channel (SPICE=1 mode in si-test.sh).
    # Exits cleanly when no spice channel is present (default gtk mode),
    # so it is safe to autostart unconditionally.
    exec spice-vdagent

    # --- App launchers / safe-image actions ---
    bindsym $mod+Return  exec foot
    bindsym $mod+d       exec fuzzel
    bindsym $mod+h       exec foot -e safe-docs
    bindsym $mod+s       exec foot sh -c 'safe-status; echo; read -rp "Press Enter to close..." _'
    bindsym $mod+Shift+o exec /run/current-system/sw/bin/safe-network-off
    bindsym $mod+Shift+i exec /run/current-system/sw/bin/safe-network-on
    bindsym $mod+Shift+q kill
    bindsym $mod+Shift+e exec swaynag -t warning -m 'Exit sway?' -b 'Yes' 'swaymsg exit'
    bindsym $mod+Shift+c reload

    # --- Focus (arrow keys; vim-style h/j/k/l omitted to keep $mod+h free) ---
    bindsym $mod+Left    focus left
    bindsym $mod+Down    focus down
    bindsym $mod+Up      focus up
    bindsym $mod+Right   focus right

    # --- Move focused window ---
    bindsym $mod+Shift+Left  move left
    bindsym $mod+Shift+Down  move down
    bindsym $mod+Shift+Up    move up
    bindsym $mod+Shift+Right move right

    # --- Layout: splits, fullscreen, floating ---
    bindsym $mod+b       splith
    bindsym $mod+v       splitv
    bindsym $mod+f       fullscreen toggle
    bindsym $mod+Shift+space floating toggle
    bindsym $mod+space   focus mode_toggle
    bindsym $mod+a       focus parent

    # --- Workspaces ---
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym $mod+5 workspace number 5
    bindsym $mod+6 workspace number 6
    bindsym $mod+7 workspace number 7
    bindsym $mod+8 workspace number 8
    bindsym $mod+9 workspace number 9
    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9

    # --- Resize mode ---
    mode "resize" {
      bindsym Left  resize shrink width  20px
      bindsym Down  resize grow   height 20px
      bindsym Up    resize shrink height 20px
      bindsym Right resize grow   width  20px
      bindsym Return mode "default"
      bindsym Escape mode "default"
    }
    bindsym $mod+r mode "resize"

    output * bg #111111 solid_color
    output Virtual-1 resolution 1920x1080

    bar {
      status_command i3status
    }
  '';

  # Explicitly tell fontconfig where JetBrains Mono lives in the Nix store.
  # fonts.packages puts fonts there but the live-ISO fontconfig cache may not
  # include them; an explicit <dir> makes fontconfig scan on demand.
  environment.etc."fonts/conf.d/80-safe-live-fonts.conf".text = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <dir>${pkgs.jetbrains-mono}/share/fonts</dir>
      <alias>
        <family>monospace</family>
        <prefer><family>JetBrains Mono</family></prefer>
      </alias>
    </fontconfig>
  '';

  # Write foot config directly to user home — reliable regardless of XDG lookup.
  # Activation runs as root; chown the whole .config tree so anything else
  # writing there (LibreWolf, etc.) has access.
  system.activationScripts.footConfig = lib.stringAfter [ "users" ] ''
    install -d -o nixos -g users -m 700 /home/nixos/.config
    install -d -o nixos -g users -m 700 /home/nixos/.config/foot
    cat > /home/nixos/.config/foot/foot.ini <<'EOF'
    [main]
    font=JetBrains Mono:size=11
    EOF
    chown nixos:users /home/nixos/.config/foot/foot.ini
    chmod 644 /home/nixos/.config/foot/foot.ini
  '';

  # Dark mako notification style.
  environment.etc."xdg/mako/config".text = ''
    background-color=#1e1e2e
    text-color=#cdd6f4
    border-color=#89b4fa
    border-radius=6
    border-size=2
    default-timeout=4000
    font=JetBrains Mono 10
  '';

  fonts.packages = with pkgs; [ jetbrains-mono ];

  environment.systemPackages = with pkgs; [
    fontconfig
    sway
    swaybg
    swayidle
    swaylock
    foot
    fuzzel
    i3status
    mako
    wl-clipboard
  ];
}
