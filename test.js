// node test.js
const fs = require("fs")
const assert = require("assert")
const load = (file, names) => new Function(fs.readFileSync(__dirname + "/" + file, "utf8").replace(".pragma library", "") + "; return { " + names + " }")()
const M = load("Model.js", "parseUpdateInfo, normalizeRepo, sourceFor, pickAsset, versionOf, compareVersions, updateFor, readRepos, withRepo, statusLine")
const tr = (s, ...a) => a.reduce((out, v, i) => out.split("%" + (i + 1)).join(String(v)), s)

// Update info built into the AppImage: only GitHub releases.
assert.deepStrictEqual(M.parseUpdateInfo("gh-releases-zsync|o|app|latest|App-*x86_64.AppImage.zsync\n"),
  { repo: "o/app", tag: "latest", glob: "App-*x86_64.AppImage" })
assert.strictEqual(M.parseUpdateInfo("zsync|https://x/App.AppImage.zsync"), null)
assert.strictEqual(M.parseUpdateInfo(""), null)

// A typed repository: owner/repo or a GitHub link to it.
assert.strictEqual(M.normalizeRepo(" o/app "), "o/app")
assert.strictEqual(M.normalizeRepo("https://github.com/o/app.js/releases"), "o/app.js")
assert.strictEqual(M.normalizeRepo("github.com/o/app.git"), "o/app")
assert.strictEqual(M.normalizeRepo("not a repo"), "")
assert.strictEqual(M.normalizeRepo(""), "")

// The typed repository beats the built-in one; neither — no source.
const app = { file: "App.AppImage", version: "1.2.0", mtime: 1000, update: "gh-releases-zsync|o|app|latest|App-*.AppImage.zsync", registered: true }
assert.deepStrictEqual(M.sourceFor(app, {}), { repo: "o/app", tag: "latest", glob: "App-*.AppImage" })
assert.deepStrictEqual(M.sourceFor(app, { "App.AppImage": "me/fork" }), { repo: "me/fork", tag: "latest", glob: "" })
assert.strictEqual(M.sourceFor({ file: "B.AppImage", update: "" }, { "App.AppImage": "me/fork" }), null)

// Which file of the release: by the mask, else the x86_64 AppImage.
const asset = (name, at) => ({ name, browser_download_url: "https://dl/" + name, updated_at: at || "1970-01-01T00:20:00Z" })
const rel = { tag_name: "v1.10.0", assets: [asset("App-1.10.0-arm64.AppImage"), asset("App-1.10.0.AppImage.zsync"), asset("App-1.10.0-x86_64.AppImage"), asset("App.deb")] }
assert.strictEqual(M.pickAsset(rel, "").name, "App-1.10.0-x86_64.AppImage")
assert.strictEqual(M.pickAsset(rel, "App-*-arm64.AppImage").name, "App-1.10.0-arm64.AppImage")
assert.strictEqual(M.pickAsset({ assets: [asset("App-arm64.AppImage")] }, ""), null)
assert.strictEqual(M.pickAsset({ assets: [asset("App.appimage")] }, "").name, "App.appimage")
assert.strictEqual(M.pickAsset({}, ""), null)

// Versions compare by number, whatever the tag looks like.
assert.strictEqual(M.versionOf("v1.10.0"), "1.10.0")
assert.strictEqual(M.versionOf("release-2.3"), "2.3")
assert.strictEqual(M.versionOf("nightly"), "")
assert.ok(M.compareVersions("1.10.0", "1.9.3") > 0)
assert.ok(M.compareVersions("1.2", "1.2.0") === 0)
assert.ok(M.compareVersions("1.2.0", "1.10") < 0)

// An update: a newer version; without one inside the AppImage — a newer file in the release.
assert.deepStrictEqual(M.updateFor(app, rel, ""), { version: "1.10.0", url: "https://dl/App-1.10.0-x86_64.AppImage" })
assert.strictEqual(M.updateFor(Object.assign({}, app, { version: "1.10.0" }), rel, ""), null)
assert.strictEqual(M.updateFor(Object.assign({}, app, { version: "2.0" }), rel, ""), null)
const bare = Object.assign({}, app, { version: "" })
assert.deepStrictEqual(M.updateFor(bare, rel, ""), { version: "1.10.0", url: "https://dl/App-1.10.0-x86_64.AppImage" })
assert.strictEqual(M.updateFor(Object.assign({}, bare, { mtime: 2000 }), rel, ""), null)
assert.strictEqual(M.updateFor(app, { tag_name: "v9", assets: [] }, ""), null)
assert.deepStrictEqual(M.updateFor(bare, { tag_name: "nightly", assets: [asset("App.AppImage")] }, ""), { version: "nightly", url: "https://dl/App.AppImage" })

// Settings: repos in this plugin's entry of shell.json; an empty value drops the line.
const cfg = { plugins: [{ id: "x" }, { id: "predmaxim.appimages", repos: { "A.AppImage": "o/a", bad: 3 } }] }
assert.deepStrictEqual(M.readRepos(JSON.stringify(cfg), "predmaxim.appimages"), { "A.AppImage": "o/a" })
assert.deepStrictEqual(M.readRepos("{}", "predmaxim.appimages"), {})
assert.deepStrictEqual(M.readRepos("{broken", "predmaxim.appimages"), {})
assert.deepStrictEqual(M.withRepo({ "A.AppImage": "o/a" }, "B.AppImage", "https://github.com/o/b"), { "A.AppImage": "o/a", "B.AppImage": "o/b" })
assert.deepStrictEqual(M.withRepo({ "A.AppImage": "o/a" }, "A.AppImage", ""), {})

// The second line of a row.
assert.strictEqual(M.statusLine(app, null, false, tr), "1.2.0 · In the menu")
assert.strictEqual(M.statusLine(bare, { version: "2" }, false, tr), "2 available")
assert.strictEqual(M.statusLine(Object.assign({}, app, { registered: false }), null, true, tr), "1.2.0 · Not in the menu · Check failed")

// Every tr() in the QML has a Russian line, and every Russian line is used.
const I = load("I18n.js", "TABLES")
const used = new Set()
for (const f of ["Panel.qml", "Model.js"])
  for (const m of fs.readFileSync(__dirname + "/" + f, "utf8").matchAll(/\btr\("((?:[^"\\]|\\.)*)"/g)) {
    const key = JSON.parse(`"${m[1]}"`)
    used.add(key)
    assert.ok(Object.prototype.hasOwnProperty.call(I.TABLES.ru, key), f + ": no ru for " + key)
  }
for (const key of Object.keys(I.TABLES.ru)) assert.ok(used.has(key), "unused ru: " + key)

console.log("ok")
