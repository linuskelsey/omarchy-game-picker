// Pure data helpers for the game-picker overlay: parse scan.sh's JSON and
// filter it by a search query. No launching logic here — see GamePicker.qml.

function parseGames(raw) {
  try {
    var data = JSON.parse(String(raw || ""))
    return Array.isArray(data) ? data : []
  } catch (e) {
    return []
  }
}

function normalizedQuery(query) {
  return String(query || "").trim().toLowerCase()
}

function matchText(game) {
  return (String(game.name || "") + " " + String(game.platform || "")).toLowerCase()
}

function filterGames(games, query) {
  var values = Array.isArray(games) ? games : []
  var needle = normalizedQuery(query)
  if (!needle) return values.slice().sort(byName)

  var out = []
  for (var i = 0; i < values.length; i++) {
    var game = values[i]
    if (game && matchText(game).indexOf(needle) >= 0) out.push(game)
  }
  return out.sort(byName)
}

function byName(a, b) {
  var an = String((a && a.name) || "").toLowerCase()
  var bn = String((b && b.name) || "").toLowerCase()
  return an < bn ? -1 : (an > bn ? 1 : 0)
}

// platformGlyph: single-letter fallback badge when a game has no icon image.
function platformGlyph(platform) {
  return String(platform || "?").charAt(0).toUpperCase()
}

if (typeof module !== "undefined") {
  module.exports = {
    parseGames: parseGames,
    normalizedQuery: normalizedQuery,
    filterGames: filterGames,
    platformGlyph: platformGlyph
  }
}
