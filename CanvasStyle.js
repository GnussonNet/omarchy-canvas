.pragma library

function courseColor(courseId) {
    var colors = ["#7aa2f7", "#9ece6a", "#e0af68", "#bb9af7", "#7dcfff", "#f7768e"]
    var key = String(courseId)
    var hash = 0
    for (var i = 0; i < key.length; i++) hash = (hash * 31 + key.charCodeAt(i)) >>> 0
    return colors[hash % colors.length]
}
