std = "lua54"

globals = {
  "vim",
  "describe",
  "it",
  "before_each",
  "after_each",
  "assert"
}

max_line_length = 120
ignore = {
  "631"
}

files["tests/**/*.lua"] = {
  globals = {
    "vim",
    "describe",
    "it",
    "before_each",
    "after_each",
    "assert"
  }
}
