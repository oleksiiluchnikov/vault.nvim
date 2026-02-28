--- vault.scoring — Merge candidate scoring with Rust-powered similarity + cluster proximity.
--- Orchestrates vault_core.score_merge_candidates() and optional wikilink cluster BFS.

local M = {}

--- Score merge candidates for a given note.
--- Uses Rust engine for slug similarity + tag Jaccard,
--- optionally adds cluster proximity bonus from wikilink graph.
---
---@param query_slug string  slug of the source note
---@param query_tags string[]  tags of the source note
---@param candidates { slug: string, tags: string[], path: string }[]
---@param opts? { limit?: integer, cluster_note?: table, cluster_depth?: integer }
---@return { slug: string, path: string, score: number, slug_sim: number, tag_overlap: number, cluster: number }[]
function M.score_merge_candidates(query_slug, query_tags, candidates, opts)
  opts = opts or {}
  local limit = opts.limit or 50

  -- Build Rust-compatible candidate list
  local rust_candidates = {}
  local path_map = {}  -- slug → path for re-attaching after scoring
  for _, c in ipairs(candidates) do
    table.insert(rust_candidates, { slug = c.slug, tags = c.tags or {} })
    path_map[c.slug] = c.path
  end

  -- Call Rust scoring engine
  local scored = {}
  local ok_core, core = pcall(require, "vault_core")
  if ok_core and core.score_merge_candidates then
    local ok, result = pcall(core.score_merge_candidates, query_slug, query_tags or {}, rust_candidates, limit)
    if ok and result then
      scored = result
    end
  end

  -- If Rust unavailable, fall back to returning all candidates unscored
  if #scored == 0 then
    for _, c in ipairs(candidates) do
      table.insert(scored, {
        slug = c.slug,
        score = 0,
        slug_sim = 0,
        tag_overlap = 0,
      })
    end
    -- Sort alphabetically as fallback
    table.sort(scored, function(a, b) return a.slug < b.slug end)
    if #scored > limit then
      local trimmed = {}
      for i = 1, limit do trimmed[i] = scored[i] end
      scored = trimmed
    end
  end

  -- Optional: cluster proximity bonus
  local cluster_map = nil  -- slug → true for notes within N hops
  if opts.cluster_note then
    local ok_cluster, cluster_result = pcall(function()
      local Notes = require("vault.notes")
      local notes = Notes()
      local depth = opts.cluster_depth or 2
      local cluster = notes:to_cluster(opts.cluster_note, depth)
      return cluster.map or {}
    end)
    if ok_cluster and cluster_result then
      cluster_map = cluster_result
    end
  end

  -- Attach path and cluster bonus, recompute final score
  local results = {}
  for _, s in ipairs(scored) do
    local cluster_bonus = 0
    if cluster_map and cluster_map[s.slug] then
      cluster_bonus = 1.0
    end

    local final_score
    if cluster_map then
      -- With cluster: rebalance weights
      final_score = 0.4 * s.slug_sim + 0.3 * s.tag_overlap + 0.3 * cluster_bonus
    else
      -- Without cluster: use Rust score directly
      final_score = s.score
    end

    table.insert(results, {
      slug = s.slug,
      path = path_map[s.slug],
      score = final_score,
      slug_sim = s.slug_sim,
      tag_overlap = s.tag_overlap,
      cluster = cluster_bonus,
    })
  end

  -- Re-sort by final score (cluster may have changed ordering)
  table.sort(results, function(a, b) return a.score > b.score end)

  return results
end

--- Convenience: score using only slug similarity (for wikilinks picker).
--- Wraps vault_core.suggest().
---@param query_slug string
---@param all_slugs string[]
---@param limit? integer
---@return { slug: string, score: number }[]
function M.suggest(query_slug, all_slugs, limit)
  limit = limit or 20
  local ok_core, core = pcall(require, "vault_core")
  if not ok_core or not core.suggest then
    return {}
  end
  local ok, result = pcall(core.suggest, query_slug, all_slugs, limit)
  if not ok or not result then
    return {}
  end

  -- Flatten strategy results: take best score per slug across all strategies
  local best = {}  -- slug → score
  for _, candidates in pairs(result) do
    for _, c in ipairs(candidates) do
      local slug = c.slug or c[1] or ""
      local score = c.score or c[2] or 0
      if slug ~= "" and (not best[slug] or score > best[slug]) then
        best[slug] = score
      end
    end
  end

  -- Convert to sorted list
  local list = {}
  for slug, score in pairs(best) do
    table.insert(list, { slug = slug, score = score })
  end
  table.sort(list, function(a, b) return a.score > b.score end)
  if #list > limit then
    local trimmed = {}
    for i = 1, limit do trimmed[i] = list[i] end
    list = trimmed
  end
  return list
end

return M
