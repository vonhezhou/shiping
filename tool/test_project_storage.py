#!/usr/bin/env python3
"""Run production project/draft storage against isolated temporary files."""
import pathlib
import subprocess
import tempfile

root = pathlib.Path(__file__).resolve().parents[1]
source = (root / "macos/Runner/MainFlutterWindow.swift").read_text()
production = source[source.index("final class ProjectFileStore {"):]
with tempfile.TemporaryDirectory(prefix="fruler-project-") as directory:
    folder = pathlib.Path(directory)
    script = folder / "main.swift"
    script.write_text("import Cocoa\n" + production + r'''
func check(_ value: Bool) { precondition(value) }
let folder = URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
let suite = "fruler.storage-test.\(UUID().uuidString)"
let defaults = UserDefaults(suiteName:suite)!
defer { defaults.removePersistentDomain(forName:suite) }
let draft = folder.appendingPathComponent("draft.json")
let project = folder.appendingPathComponent("original.fruler")
let store = ProjectFileStore(defaults:defaults,draftURL:draft)
check(try store.loadDraft() == nil)
try store.saveDraft("draft-one")
check(try store.loadDraft() == "draft-one")
try store.saveDraft("draft-two")
check(try String(contentsOf:draft,encoding:.utf8) == "draft-two")
let location = try store.write("original",to:project)
check(location["path"] == project.path)
let restarted = ProjectFileStore(defaults:defaults,draftURL:draft)
check(restarted.recent().count == 1)
let resolved = try restarted.resolve(project.path)
check(try restarted.read(resolved)["text"] == "original")
try restarted.saveDraft("recovery-only")
check(try String(contentsOf:project,encoding:.utf8) == "original")
_ = try restarted.write("edited",to:resolved)
check(try restarted.read(resolved)["text"] == "edited")
check(restarted.recent().count == 1)
do { _ = try restarted.resolve("/unselected/file.fruler"); assertionFailure("unselected access") } catch {}
do { _ = try restarted.write("bad",to:folder); assertionFailure("directory overwrite") } catch {}
check(try String(contentsOf:project,encoding:.utf8) == "edited")
let missing = folder.appendingPathComponent("missing.fruler")
do { _ = try restarted.write("bad",to:missing,mustExist:true); assertionFailure("recreate missing original") } catch {}
check(!FileManager.default.fileExists(atPath:missing.path))
try restarted.saveDraft(nil)
check(try restarted.loadDraft() == nil)
try restarted.saveDraft(nil)
try Data([0xff,0xfe]).write(to:draft)
do { _ = try restarted.loadDraft(); assertionFailure("invalid utf8") } catch {}
check(FileManager.default.fileExists(atPath:draft.path))
for index in 0..<14 { _ = try store.write("{}",to:folder.appendingPathComponent("\(index).fruler")) }
check(store.recent().count == 12)
print("项目存储原生回归通过：书签重启解析、原文件保存、最近项目上限、独立草稿原子写入与损坏保护")
''')
    binary = folder / "storage-probe"
    subprocess.run(["xcrun", "swiftc", str(script), "-o", str(binary)], check=True)
    subprocess.run([str(binary), str(folder)], check=True, timeout=30)
