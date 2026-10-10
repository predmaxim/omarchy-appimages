.pragma library
// What appimages.sh can't decide: where an AppImage updates from, which file
// of a GitHub release is it, and whether that one is newer.

// "gh-releases-zsync|owner|repo|tag|mask.zsync" built into the AppImage; other kinds — null.
function parseUpdateInfo(text) {
  var parts = String(text || "").trim().split("|")
  if (parts[0] !== "gh-releases-zsync" || parts.length < 5) return null
  return { repo: parts[1] + "/" + parts[2], tag: parts[3], glob: parts[4].replace(/\.zsync$/, "") }
}

// "owner/repo" out of what was typed: owner/repo or a GitHub link; else "".
function normalizeRepo(text) {
  var s = String(text || "").trim().replace(/^(https?:\/\/)?(www\.)?github\.com\//, "")
  var m = s.match(/^([\w.-]+)\/([\w.-]+?)(\.git)?(\/.*)?$/)
  return m ? m[1] + "/" + m[2] : ""
}

// The typed repository wins over the built-in update info.
function sourceFor(app, repos) {
  var repo = normalizeRepo((repos || {})[app.file])
  if (repo) return { repo: repo, tag: "latest", glob: "" }
  return parseUpdateInfo(app.update)
}

function globToRegExp(glob) {
  var escaped = glob.replace(/[.+^${}()|[\]\\]/g, "\\$&").replace(/\*/g, ".*").replace(/\?/g, ".")
  return new RegExp("^" + escaped + "$")
}

// The release file: by the mask, else an x86_64 (or arch-less) AppImage.
function pickAsset(release, glob) {
  var assets = (release && release.assets) || []
  var match = glob ? globToRegExp(glob) : /\.appimage$/i
  var found = assets.filter(function(a) {
    return match.test(a.name) && (glob || !/(aarch64|arm64|armhf|armv7|i[36]86)/i.test(a.name))
  })
  var x64 = found.filter(function(a) { return /(x86_64|amd64|x64)/i.test(a.name) })
  return x64[0] || found[0] || null
}

function versionOf(text) {
  var m = String(text || "").match(/\d+(\.\d+)*/)
  return m ? m[0] : ""
}

function compareVersions(a, b) {
  var x = a.split("."), y = b.split(".")
  for (var i = 0; i < Math.max(x.length, y.length); i++) {
    var d = (Number(x[i]) || 0) - (Number(y[i]) || 0)
    if (d) return d
  }
  return 0
}

// { version, url } when the release is newer than the file, else null. With
// no version inside the AppImage (or in the tag), a release file newer than
// the AppImage on disk counts.
function updateFor(app, release, glob) {
  var asset = pickAsset(release, glob)
  if (!asset) return null
  var latest = versionOf(release.tag_name), current = versionOf(app.version)
  var newer = latest && current
    ? compareVersions(latest, current) > 0
    : Date.parse(asset.updated_at) / 1000 > app.mtime
  return newer ? { version: latest || String(release.tag_name), url: asset.browser_download_url } : null
}

// { file: "owner/repo" } from this plugin's entry in shell.json.
function readRepos(text, id) {
  var cfg
  try { cfg = JSON.parse(text) } catch (e) { return {} }
  var entry = ((cfg && cfg.plugins) || []).filter(function(p) { return p && p.id === id })[0]
  var repos = (entry && entry.repos) || {}
  var out = {}
  for (var file in repos) if (typeof repos[file] === "string" && repos[file]) out[file] = repos[file]
  return out
}

function withRepo(repos, file, text) {
  var out = {}
  for (var f in repos) if (f !== file) out[f] = repos[f]
  var repo = normalizeRepo(text)
  if (repo) out[file] = repo
  return out
}

function statusLine(app, update, failed, tr) {
  if (update) return tr("%1 available", update.version)
  var parts = []
  if (app.version) parts.push(app.version)
  parts.push(app.registered ? tr("In the menu") : tr("Not in the menu"))
  if (failed) parts.push(tr("Check failed"))
  return parts.join(" · ")
}
