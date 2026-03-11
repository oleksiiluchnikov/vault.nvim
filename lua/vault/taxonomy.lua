local internal = require("vault.taxonomy.internal")

local M = {}

M.kind_choices = internal.kind_choices
M.ensure_category_choice = internal.ensure_category_choice
M.apply_choice_to_paths = internal.apply_choice_to_paths
M.grid_process_opts = internal.grid_process_opts

M.classify_notes = require("vault.taxonomy.classify").classify_notes
M.open_classify = require("vault.taxonomy.classify").open

M.audit_notes = require("vault.taxonomy.audit").audit_notes
M.open_audit = require("vault.taxonomy.audit").open

M.build_plan = require("vault.taxonomy.plan").build
M.preview = require("vault.taxonomy.rename").preview
M.apply = require("vault.taxonomy.rename").apply
M.undo_last = require("vault.taxonomy.rename").undo_last

M._get_settings = internal._get_settings
M._normalize_kind = internal._normalize_kind
M._inspect_note = internal._inspect_note
M._preview_manifest_path = internal._preview_manifest_path
M._last_apply_manifest_path = internal._last_apply_manifest_path

return M
