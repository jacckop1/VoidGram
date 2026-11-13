#!/usr/bin/env python3
"""Integrate 5 bundled Kira plugins into native VoidGram at build time."""
import json
import sys
from pathlib import Path

source = Path(sys.argv[1]).resolve()
repo = Path(__file__).resolve().parents[1]

def patch(path, old, new):
    f = source / path
    text = f.read_text()
    if text.count(old) != 1:
        raise RuntimeError("Integration anchor mismatch: " + path)
    f.write_text(text.replace(old, new, 1))

settings = 'submodules/TelegramCore/Sources/AyuGram/AyuGhostModeSettings.swift'
patch(settings, '    public var allEnabled: Bool {', '''    public mutating func kiraInstallNativePlugins() {
        for manifest in [
            AyuPluginManifest(id: "unlim_accounts", name: "Unlim Accounts", author: "@rezolvePlugins", version: "1.0", summary: "Local account limit 999", actions: [AyuPluginAction(id: "unlim_accounts", title: "Account limit 999", kind: .unlimitedAccounts)]),
            AyuPluginManifest(id: "formatted_copy", name: "Formatted Copy", author: "@meatdisk", version: "1.0.0-ios.1", summary: "Copy messages with author and date", actions: [AyuPluginAction(id: "formatted_copy", title: "Copy with details", kind: .formattedCopy)])
        ] where !plugins.installed.contains(where: { $0.manifest.id == manifest.id }) {
            try? plugins.installAndActivate(manifest)
        }
    }

    public var allEnabled: Bool {''')
patch(settings, '''        } else {
            self.value = AyuGhostModeSettings()
            self.hadLoadError = false
        }
    }
''', '''        } else {
            self.value = AyuGhostModeSettings()
            self.hadLoadError = false
        }
        #if os(iOS) && !AYU_POSTBOX_TESTS
        let marker = URL(fileURLWithPath: accountPath).appendingPathComponent(".kira-5plugins-installed")
        if !FileManager.default.fileExists(atPath: marker.path) {
            var installed = self.value
            installed.kiraInstallNativePlugins()
            let success: Bool
            if installed == self.value { success = true }
            else if let data = try? JSONEncoder().encode(installed) {
                success = (try? data.write(to: self.fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
                if success { self.value = installed }
            } else { success = false }
            if success { try? Data("1".utf8).write(to: marker, options: .atomic) }
        }
        #endif
    }
''')

def js(name, label, translation):
    text = (repo / 'code-plugins' / name / 'plugin.ayu.js').read_text()
    return json.dumps(text.replace(label, translation), ensure_ascii=False)

download = js('download-all-media', 'Скачать все медиа', 'Download All Media')
year = js('year-in-review', 'Итоги года', 'Year in Review')
runtime = 'submodules/AccountContext/Sources/AyuScriptRuntime.swift'
patch(runtime, '''    private init() {
        self.index = self.loadIndex()
    }
''', '''    private init() {
        self.index = self.loadIndex()
        self.kiraInstallScripts()
        if !UserDefaults.standard.bool(forKey: "kira.acd.initialized") {
            AyuNativePlugins.install(.albumCoverDownloader)
            UserDefaults.standard.set(true, forKey: "kira.acd.initialized")
        }
    }

    private func kiraInstallScripts() {
        guard let directory = self.directory else { return }
        let bundled: [(String, String)] = [
            ("download-all-media", ''' + download + '''),
            ("year-in-review", ''' + year + ''')
        ]
        var changed = false
        for (id, source) in bundled where !self.index.contains(where: { $0.id == id }) {
            let data = Data(source.utf8)
            guard var plugin = self.preview(data, filename: id + ".js") else { continue }
            plugin.enabled = true
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent(id + ".js"), options: .atomic)
                self.index.append(plugin)
                changed = true
            } catch { }
        }
        if changed { self.saveIndex() }
    }
''')
print("Kira: native default plugins and two JS plugins integrated")
