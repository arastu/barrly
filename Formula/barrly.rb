class Barrly < Formula
  desc "Native Liquid Glass bar for macOS with built-in widgets (SketchyBar + Übersicht inspired)"
  homepage "https://github.com/arastu/barrly"
  url "https://github.com/arastu/barrly.git",
      tag:      "v0.11.0",
      revision: "213d3a4424144dfc66cd05b9e53067845ba7e49e"
  license "MIT"
  head "https://github.com/arastu/barrly.git", branch: "main"

  depends_on :macos => :tahoe
  uses_from_macos "perl"

  # The now-playing helper is vendored by the build script (git clone); pin it here so the
  # formula build is reproducible and sandbox-friendly.
  resource "mediaremote-adapter" do
    url "https://github.com/ungive/mediaremote-adapter.git",
        revision: "0e82bf1c44ec39554fbfc402ec88a48c6ae2a0fd"
  end

  def install
    ENV.delete("CFLAGS"); ENV.delete("LDFLAGS"); ENV.delete("CXXFLAGS")
    (buildpath/"Vendor/mediaremote-adapter").install resource("mediaremote-adapter")
    system "scripts/build-adapter.sh"
    system "swift", "build", "-c", "release", "--disable-sandbox"

    stage = buildpath/"stage/MediaRemoteAdapter"
    stage.mkpath
    cp_r buildpath/"Vendor/build/MediaRemoteAdapter.framework", stage
    cp buildpath/"Vendor/build/mediaremote-adapter.pl", stage
    cp buildpath/"Vendor/build/MediaRemoteAdapterTestClient", stage
    system "scripts/bundle.sh", buildpath/".build/release/Barrly", "Barrly", "dev.barrly.app", prefix, buildpath/"stage"

    (bin/"barrly").write <<~SH
      #!/bin/bash
      # barrly            launch the bar          barrly zen|refresh|settings|lock   send a command
      # barrly sign       re-sign Barrly.app with the local "Barrly Code Signing" identity (see caveats)
      app="#{opt_prefix}/Barrly.app"
      sign() {
        kc="$HOME/Library/Keychains/barrly-signing.keychain-db"
        [ -f "$kc" ] || return 0
        /usr/bin/codesign -d -r- "$app" 2>&1 | grep -q 'certificate root' && return 0
        /usr/bin/security unlock-keychain -p barrly "$kc" 2>/dev/null || true
        /usr/bin/codesign --force --deep --keychain "$kc" --sign "Barrly Code Signing" "$app" 2>/dev/null \
          && echo "barrly: signed Barrly.app with the Barrly Code Signing identity"
      }
      case "${1:-}" in
        zen)      open "barrly://mode/zen" ;;
        refresh)  open "barrly://refresh" ;;
        settings) open "barrly://settings" ;;
        lock)     open "barrly://lock/${2:-on}" ;;
        sign)     sign ;;
        quit)     pkill -x Barrly ;;
        ""|start) sign; open -a "$app" ;;
        *) echo "usage: barrly [start|zen|refresh|settings|lock [on|off]|sign|quit]"; exit 2 ;;
      esac
    SH
  end

  service do
    run [opt_prefix/"Barrly.app/Contents/MacOS/Barrly"]
    keep_alive true
    log_path var/"log/barrly.log"
    error_log_path var/"log/barrly.log"
  end

  def caveats
    <<~EOS
      Barrly.app is at #{opt_prefix}/Barrly.app, built on this machine.

      The build is ad-hoc signed, so macOS privacy grants (Accessibility for the input lock, Calendars)
      would be lost on every upgrade. Create a stable local identity once with the repo's
      scripts/make-signing-identity.sh; `barrly start` and `barrly sign` then re-sign the app with
      it after each upgrade (Homebrew's sandbox cannot reach the keychain, so this runs outside it).

      Start it with `barrly`, or at login with either
        brew services start barrly
      or AeroSpace:
        after-startup-command = ['exec-and-forget open -a #{opt_prefix}/Barrly.app']

      Set the macOS menu bar to auto-hide and reserve the strip in your window manager.
      Commands: barrly zen | refresh | settings
    EOS
  end

  test do
    assert_predicate prefix/"Barrly.app/Contents/MacOS/Barrly", :exist?
  end
end
