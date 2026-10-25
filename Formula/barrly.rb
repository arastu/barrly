class Barrly < Formula
  desc "Native Liquid Glass bar for macOS with built-in widgets (SketchyBar + Übersicht inspired)"
  homepage "https://github.com/arastu/barrly"
  url "https://github.com/arastu/barrly.git",
      tag:      "v0.1.2",
      revision: "5856450b2c0a4ee2b5c4b93cbf61e069a6d9800c"
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
      # barrly            launch the bar          barrly zen|refresh|settings   send a command
      app="#{opt_prefix}/Barrly.app"
      case "${1:-}" in
        zen)      open "barrly://mode/zen" ;;
        refresh)  open "barrly://refresh" ;;
        settings) open "barrly://settings" ;;
        quit)     pkill -x Barrly ;;
        ""|start) open -a "$app" ;;
        *) echo "usage: barrly [start|zen|refresh|settings|quit]"; exit 2 ;;
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
      Barrly.app is at #{opt_prefix}/Barrly.app (ad-hoc signed, built on this machine).

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
