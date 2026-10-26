import SwiftUI

/// Which widgets, in which capsule, in what order. Left column: the layout; right: options of the selection.
struct WidgetsPane: View {
  @Environment(Runtime.self) private var runtime
  @ViewState private var selection: UUID? = nil

  var body: some View {
    @Bindable var store = runtime.settings
    HSplitView {
      List(selection: $selection) {
        ForEach(Side.allCases) { side in
          Section {
            ForEach(store.settings.layout[side]) { surface in
              SurfaceSection(surface: surface, side: side, selection: $selection)
            }
            Button { addSurface(to: side) } label: { Label("Add capsule", systemImage: "plus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.leading, 4)
          } header: { Text(side.title) }
        }
      }
      .listStyle(.sidebar)
      .frame(minWidth: 300)
      Group {
        if let id = selection, let spec = store.spec(id: id) { WidgetOptionsPane(spec: spec) }
        else if let id = selection, let surface = store.settings.layout.allSurfaces.first(where: { $0.id == id }) { SurfaceOptionsPane(surface: surface) }
        else { ContentUnavailableView("Select a widget", systemImage: "slider.horizontal.3", description: Text("Pick a widget or capsule to change its options.")) }
      }
      .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private func addSurface(to side: Side) {
    runtime.settings.settings.layout[side].append(Surface(name: "New capsule", widgets: []))
  }
}

private struct SurfaceSection: View {
  let surface: Surface
  let side: Side
  @Binding var selection: UUID?
  @Environment(Runtime.self) private var runtime

  var body: some View {
    DisclosureGroup(isExpanded: .constant(true)) {
      ForEach(surface.widgets) { w in
        HStack {
          Toggle("", isOn: Binding(get: { w.enabled }, set: { v in runtime.settings.update(w.id) { $0.enabled = v } })).labelsHidden().toggleStyle(.switch).controlSize(.mini)
          Image(systemName: w.kind.symbol).frame(width: 18).foregroundStyle(.secondary)
          Text(w.kind.title)
          Spacer()
          if w.hiddenInZen { Image(systemName: "moon.zzz").foregroundStyle(.tertiary).help("Hidden in zen mode") }
        }
        .tag(w.id)
        .contextMenu { Button("Remove", role: .destructive) { runtime.settings.removeWidget(w.id) } }
      }
      .onMove { from, to in runtime.settings.updateSurface(surface.id) { $0.widgets.move(fromOffsets: from, toOffset: to) } }
      AddWidgetMenu(surfaceID: surface.id)
    } label: {
      HStack {
        Image(systemName: "capsule").foregroundStyle(.secondary)
        Text(surface.name).fontWeight(.medium)
        if let t = surface.tint { Circle().fill(ResolvedTheme.preview.palette.accent(t)).frame(width: 8, height: 8) }
      }
      .tag(surface.id)
      .contextMenu { Button("Remove capsule", role: .destructive) { runtime.settings.settings.layout[side].removeAll { $0.id == surface.id } } }
    }
  }
}

private struct AddWidgetMenu: View {
  let surfaceID: UUID
  @Environment(Runtime.self) private var runtime
  var body: some View {
    let used = Set(runtime.settings.settings.layout.allWidgets.map(\.kind))
    Menu {
      ForEach(WidgetKind.allCases.filter { $0.allowsDuplicates || !used.contains($0) }) { kind in
        Button { runtime.settings.updateSurface(surfaceID) { $0.widgets.append(WidgetSpec(kind)) } } label: { Label(kind.title, systemImage: kind.symbol) }
      }
    } label: { Label("Add widget", systemImage: "plus") }
    .menuStyle(.borderlessButton).foregroundStyle(.secondary).padding(.leading, 4)
  }
}

private struct SurfaceOptionsPane: View {
  let surface: Surface
  @Environment(Runtime.self) private var runtime
  var body: some View {
    Form {
      TextField("Name", text: Binding(get: { surface.name }, set: { v in runtime.settings.updateSurface(surface.id) { $0.name = v } }))
      Picker("Tint", selection: Binding(get: { surface.tint }, set: { v in runtime.settings.updateSurface(surface.id) { $0.tint = v } })) {
        Text("None (plain glass)").tag(AccentToken?.none)
        ForEach(AccentToken.allCases) { t in Text(t.rawValue.capitalized).tag(AccentToken?.some(t)) }
      }
      Text("Glass is the functional layer: keep capsules plain and use a tint only for the one prominent item.").font(.caption).foregroundStyle(.secondary)
    }.formStyle(.grouped)
  }
}

/// Per-widget options. One pane, sections appear for the fields the widget uses.
struct WidgetOptionsPane: View {
  let spec: WidgetSpec
  @Environment(Runtime.self) private var runtime

  private func b<T>(_ kp: WritableKeyPath<WidgetSpec, T>) -> Binding<T> {
    Binding(get: { runtime.settings.spec(id: spec.id)?[keyPath: kp] ?? spec[keyPath: kp] }, set: { v in runtime.settings.update(spec.id) { $0[keyPath: kp] = v } })
  }
  private func o<T>(_ kp: WritableKeyPath<WidgetOptions, T>) -> Binding<T> { b(\.options).map(kp) }

  var body: some View {
    Form {
      Section(spec.kind.title) {
        Toggle("Enabled", isOn: b(\.enabled))
        if spec.kind != .spacer {
          Toggle("Hide in zen mode", isOn: b(\.hiddenInZen))
          Toggle("Highlight on hover", isOn: b(\.hoverable))
          Toggle("Secondary text", isOn: b(\.secondary))
          if spec.kind.defaultTint != nil || spec.kind == .appleMenu {
            Picker("Icon colour", selection: o(\.iconTint)) {
              Text("Automatic").tag("auto"); Text("Same as text").tag("none")
              ForEach(AccentToken.allCases) { Text($0.rawValue.capitalized).tag($0.rawValue) }
            }
          }
        }
      }
      switch spec.kind {
      case .clock:
        Section("Clock") {
          TextField("Format", text: o(\.clockFormat)).help("Unicode date pattern, e.g. EEE d MMM  HH:mm")
          TextField("Open on click", text: o(\.clickApp).orEmpty)
        }
      case .jalaliDate:
        Section("Jalali date") {
          TextField("Format", text: o(\.jalaliFormat)).help("d, dd, M, MM, MMMM, yyyy, EEEE")
          Toggle("Persian digits", isOn: o(\.persianDigits))
          TextField("Open on click", text: o(\.clickApp).orEmpty)
        }
      case .workspaces:
        Section("Workspaces") {
          Stepper("App icons per workspace: \(spec.options.maxIcons)", value: o(\.maxIcons), in: 0...8)
          Toggle("Hide empty workspaces", isOn: o(\.hideEmpty))
          Toggle("Show workspace names", isOn: o(\.showIds))
        }
      case .frontApp:
        Section("Front app") { Toggle("Show icon", isOn: o(\.showIcon)); Toggle("Show name", isOn: o(\.showName)) }
      case .nowPlaying:
        Section("Now playing") {
          TextField("Format", text: o(\.nowPlayingFormat)).help("{title} and {artist}")
          Stepper("Max characters: \(spec.options.maxChars)", value: o(\.maxChars), in: 10...120)
          Toggle("Include browser tabs (Safari, Chrome…)", isOn: o(\.includeBrowsers))
          Text(runtime.nowPlaying.usingAdapter ? "Source: system now-playing service" : "Source: Music / Spotify polling").font(.caption).foregroundStyle(.secondary)
        }
      case .cpu, .ram:
        Section("Sampling") {
          Stepper("Every \(Int(spec.options.interval)) s", value: o(\.interval), in: 1...60)
          TextField("Open on click", text: o(\.clickApp).orEmpty)
        }
      case .wifi:
        Section("Wi‑Fi") {
          Picker("Show", selection: o(\.wifiShow)) { Text("Last octet").tag(WidgetOptions.WifiShow.lastOctet); Text("Full IP").tag(WidgetOptions.WifiShow.fullIP); Text("Icon only").tag(WidgetOptions.WifiShow.none) }
          Text("Click copies the IP address.").font(.caption).foregroundStyle(.secondary)
        }
      case .battery:
        Section("Battery") { Stepper("Warn below \(spec.options.warnBelow)%", value: o(\.warnBelow), in: 5...50, step: 5); Toggle("Show percentage", isOn: o(\.showPercent)) }
      case .inputLock:
        Section("Input lock") {
          LabeledContent("Lock shortcut") { ShortcutRecorder(chord: o(\.lockChord), onRecording: { runtime.inputLock.hotKeySuspended = $0 }) }
          LabeledContent("Unlock shortcut") { ShortcutRecorder(chord: o(\.unlockChord), onRecording: { runtime.inputLock.hotKeySuspended = $0 }) }
          if spec.options.lockChord == spec.options.unlockChord { Text("Same keys: press once to lock, again to unlock.").font(.caption).foregroundStyle(.secondary) }
          Toggle("Show unlock hint while locked", isOn: o(\.showName))
          Text("Click blocks every keyboard, mouse and trackpad, built-in or external, until you press \(spec.options.unlockChord.display). The screen stays on. Also: barrly://lock, lock/on, lock/off.").font(.caption).foregroundStyle(.secondary)
          if runtime.inputLock.authorized { Text("Accessibility permission: granted").font(.caption).foregroundStyle(.secondary) }
          else {
            Text("Accessibility permission is required. After a Barrly upgrade macOS may ask again.").font(.caption).foregroundStyle(.red)
            Button("Open Accessibility settings") { runtime.inputLock.requestAuthorization(); runtime.inputLock.openAccessibilitySettings() }
          }
          if let e = runtime.inputLock.lastError { Text(e).font(.caption).foregroundStyle(.red) }
        }
      case .vpn:
        Section("VPN") {
          Toggle("Show name", isOn: o(\.showName))
          Stepper("Name length: \(spec.options.clipChars)", value: o(\.clipChars), in: 4...40)
          TextField("Open on click (default: VPN settings)", text: o(\.clickApp).orEmpty)
          Text(runtime.vpn.state.active ? "Connected: " + runtime.vpn.state.connections.map(\.name).joined(separator: ", ") : "No VPN connected. The widget appears only while one is.").font(.caption).foregroundStyle(.secondary)
        }
      case .volume:
        Section("Volume") {
          Toggle("Show percentage", isOn: o(\.showPercent))
          Stepper("Scroll step: \(spec.options.volumeStep)%", value: o(\.volumeStep), in: 1...25)
          Text(runtime.volume.state.present ? "Output: \(runtime.volume.state.deviceName). Click mutes, scrolling changes the level." : "No output device with a software volume.").font(.caption).foregroundStyle(.secondary)
        }
      case .inputSource:
        Section("Input source labels") {
          InputSourceMapEditor(map: o(\.inputSourceMap), currentID: runtime.inputSource.state.id)
        }
      case .meeting:
        Section("Meeting") {
          Stepper("Title length: \(spec.options.clipChars)", value: o(\.clipChars), in: 6...60)
          Stepper("\"Soon\" within \(spec.options.soonMinutes) min", value: o(\.soonMinutes), in: 1...60)
          if !runtime.calendar.authorized { Text("Calendar access is not granted. Allow Barrly in System Settings › Privacy & Security › Calendars.").font(.caption).foregroundStyle(.red) }
        }
      case .spacer:
        Section("Spacer") { Slider(value: o(\.width), in: 2...40, step: 1) { Text("Width: \(Int(spec.options.width)) pt") } }
      case .appleMenu:
        Section { Text("Click refreshes every widget. Right‑click opens these settings.").font(.caption).foregroundStyle(.secondary) }
      }
    }
    .formStyle(.grouped)
  }
}

private struct InputSourceMapEditor: View {
  @Binding var map: [String: String]
  let currentID: String
  @ViewState private var newID = ""; @ViewState private var newLabel = ""
  var body: some View {
    ForEach(map.keys.sorted(), id: \.self) { k in
      HStack { Text(k).font(.caption).lineLimit(1).truncationMode(.middle); Spacer()
        TextField("Label", text: Binding(get: { map[k] ?? "" }, set: { map[k] = $0 })).frame(width: 60)
        Button(role: .destructive) { map[k] = nil } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain) }
    }
    HStack { TextField("Input source id", text: $newID).font(.caption); TextField("Label", text: $newLabel).frame(width: 60)
      Button { guard !newID.isEmpty else { return }; map[newID] = newLabel; newID = ""; newLabel = "" } label: { Image(systemName: "plus.circle") }.buttonStyle(.plain) }
    HStack { Text("Current: \(currentID)").font(.caption).foregroundStyle(.secondary); Button("Use") { newID = currentID }.controlSize(.mini) }
  }
}

extension Binding {
  func map<T>(_ kp: WritableKeyPath<Value, T>) -> Binding<T> {
    Binding<T>(get: { wrappedValue[keyPath: kp] }, set: { wrappedValue[keyPath: kp] = $0 })
  }
}
extension Binding where Value == String? {
  var orEmpty: Binding<String> { Binding<String>(get: { wrappedValue ?? "" }, set: { wrappedValue = $0.isEmpty ? nil : $0 }) }
}
