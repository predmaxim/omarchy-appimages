.pragma library
// Interface text in other languages, keyed by the English text itself, so a
// string missing from a table shows in English. tr("%1 available", x) fills in
// %1, %2… after the lookup. The same scheme as predmaxim.todo.
var TABLES = {
  ru: {
    "AppImages": "AppImage", "In the menu: %1 of %2": "В меню: %1 из %2",
    "Checking for updates…": "Проверяю обновления…", "Updates: %1": "Обновления: %1", "No updates": "Обновлений нет",
    "No update sources: see settings": "Неоткуда проверять: см. настройки",
    "Check for updates": "Проверить обновления", "Open folder": "Открыть папку", "Settings": "Настройки", "Back": "Назад",
    "%1 available": "доступна %1", "In the menu": "в меню", "Not in the menu": "не в меню", "Check failed": "не удалось проверить",
    "Update": "Обновить", "Delete": "Удалить", "Cancel": "Отмена", "Delete %1?": "Удалить %1?",
    "Add to the menu": "Добавить в меню", "Remove from the menu": "Убрать из меню",
    "No AppImages yet: put files into ~/AppImages.": "AppImage пока нет: положи файлы в ~/AppImages.",
    "GITHUB REPOSITORY · OWNER/REPO OR LINK": "GITHUB-РЕПОЗИТОРИЙ · OWNER/REPO ИЛИ ССЫЛКА",
    "Built in: %1": "встроено: %1", "Failed: %1": "Не удалось: %1"
  }
}

// Text follows LC_MESSAGES, overridden by LC_ALL and defaulting to LANG, as
// the system splits it. env is name -> value (Quickshell.env in QML).
function textLanguage(env) {
  var names = ["LC_ALL", "LC_MESSAGES", "LANG"]
  for (var i = 0; i < names.length; i++) {
    var v = String(env(names[i]) || "").split(".")[0].split("@")[0]
    if (v && v !== "C" && v !== "POSIX") {
      var l = v.slice(0, 2).toLowerCase()
      return TABLES[l] ? l : "en"
    }
  }
  return "en"
}

function translator(lang) {
  var table = TABLES[lang] || {}
  return function(text) {
    var out = Object.prototype.hasOwnProperty.call(table, text) ? table[text] : text
    for (var i = 1; i < arguments.length; i++) out = out.split("%" + i).join(String(arguments[i]))
    return out
  }
}
