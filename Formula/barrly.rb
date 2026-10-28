class Barrly < Formula
  desc "Native Liquid Glass bar for macOS with built-in widgets (SketchyBar + Übersicht inspired)"
  homepage "https://github.com/arastu/barrly"
  url "https://github.com/arastu/barrly.git",
      tag:      "v0.13.1",
      revision: "dcbfcf17900b6f30c3ccea1215727ab8b230a3de"
  license "MIT"
  head "https://github.com/arastu/barrly.git", branch: "main"

  # Prebuilt on Apple Silicon with the macOS 26 deployment target; one tarball serves every tag.
  bottle do
    root_url "https://github.com/arastu/barrly/releases/download/v0.13.1"
    sha256 cellar: :any, arm64_golden_gate: "162033ea4f4477e09a20d8b1a9d102773ef564138b213e9cd48a4bcc6a911b0a"
    sha256 cellar: :any, arm64_tahoe: "162033ea4f4477e09a20d8b1a9d102773ef564138b213e9cd48a4bcc6a911b0a"
  end

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
    # Always ad-hoc here (bottles are shared); `barrly` re-signs with the user's local identity afterwards.
    ENV["BARRLY_SIGN_IDENTITY"] = "-"
    (buildpath/"Vendor/mediaremote-adapter").install resource("mediaremote-adapter")
    system "scripts/build-adapter.sh"
    system "swift", "build", "-c", "release", "--disable-sandbox"

    # The now-playing helper lives beside the .app, not inside it: Homebrew rewrites the perl shebang
    # and the framework's install name after `install`, which would break the app's code-signature seal.
    adapter = prefix/"MediaRemoteAdapter"
    adapter.mkpath
    cp_r buildpath/"Vendor/build/MediaRemoteAdapter.framework", adapter
    cp buildpath/"Vendor/build/mediaremote-adapter.pl", adapter
    cp buildpath/"Vendor/build/MediaRemoteAdapterTestClient", adapter
    system "scripts/bundle.sh", buildpath/".build/release/Barrly", "Barrly", "dev.barrly.app", prefix
    libexec.install "scripts/make-signing-identity.sh"

    (bin/"barrly").write <<~SH
      #!/bin/bash
      # barrly            launch the bar          barrly zen|refresh|settings|lock|awake   send a command
      # barrly sign       (re)create the local "Barrly Code Signing" identity and re-sign Barrly.app with it,
      #                   so macOS privacy grants (Accessibility, Calendars) survive upgrades
      app="#{opt_prefix}/Barrly.app"
      kc="$HOME/Library/Keychains/barrly-signing.keychain-db"
      make_identity() {
        [ -f "$kc" ] && return 0
        [ -t 0 ] || return 1   # no terminal: leave the ad-hoc signature, `barrly sign` later creates it
        echo "barrly: creating a local code-signing identity so privacy grants survive upgrades (macOS may ask for your password)"
        /bin/bash "#{opt_libexec}/make-signing-identity.sh" >/dev/null
      }
      sign() {
        make_identity || return 0
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
        awake)    open "barrly://awake/${2:-on}" ;;
        sign)     sign ;;
        quit)     pkill -x Barrly ;;
        run)      sign >/dev/null; exec "$app/Contents/MacOS/Barrly" ;;   # brew services
        ""|start) sign; open -a "$app" ;;
        *) echo "usage: barrly [start|zen|refresh|settings|lock [on|off]|awake [on|off]|sign|quit]"; exit 2 ;;
      esac
    SH
  end

  service do
    run [opt_bin/"barrly", "run"]
    keep_alive true
    log_path var/"log/barrly.log"
    error_log_path var/"log/barrly.log"
  end

  def caveats
    <<~EOS
      Barrly.app is at #{opt_prefix}/Barrly.app.

      Start it with `barrly`. The first run creates a local code-signing identity and signs the app
      with it, so macOS privacy grants (Accessibility for the input lock, Calendars) survive upgrades;
      macOS may ask for your password once. Start it at login with either
        brew services start barrly
      or AeroSpace:
        after-startup-command = ['exec-and-forget #{opt_bin}/barrly']

      Set the macOS menu bar to auto-hide and reserve the strip in your window manager.
      Commands: barrly zen | refresh | settings | lock | awake | sign | quit
    EOS
  end

  test do
    assert_predicate prefix/"Barrly.app/Contents/MacOS/Barrly", :exist?
  end
end
