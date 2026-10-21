# Agent Hub settings

Managed by `scripts/sync-sb-space.sh` from `silverbullet/agent-hub.md` in the agent-share-poc repo. Changes here are overwritten by the next `make local-up` or `make deploy`; put your own settings in [[CONFIG]].

## Font

D2KodingLigature Nerd Font, served from this space (`make sb-fonts`) so every device shows the same font.

```space-style
@font-face {
  font-family: "D2Koding Space";
  src: url("/.fs/Library/agent-hub/fonts/D2KodingLigatureNerdFont-Regular.woff2") format("woff2");
  font-weight: 400;
  font-display: swap;
}
@font-face {
  font-family: "D2Koding Space";
  src: url("/.fs/Library/agent-hub/fonts/D2KodingLigatureNerdFont-Bold.woff2") format("woff2");
  font-weight: 700;
  font-display: swap;
}
:root {
  --editor-font: "D2Koding Space", "D2KodingLigature Nerd Font", "D2Coding", "Menlo", monospace;
  --ui-font: "D2Koding Space", "D2KodingLigature Nerd Font", "D2Coding", "Menlo", monospace;
}
```

## Theme

GitHub Light Default and Dark Default colors on SilverBullet's own theme variables, so `Editor: Toggle Dark Mode` switches between them as before.

```space-style
/* GitHub Light Default and Dark Default colors (@primer/primitives 10.7.0, MIT) on SilverBullet's theme variables. */
html {
  --ui-accent-color: #0969da;
  --ui-accent-contrast-color: #ffffff;
  --link-color: #0969da;
  --link-missing-color: #bc4c00;
  --link-invalid-color: #8250df;
  --meta-color: #cf222e;
  --meta-subtle-color: #59636e;
  --subtle-color: #59636e;
  --subtle-background-color: #818b981f;
  --ui-surface-border-color: #d1d9e0;
  --root-background-color: #ffffff;
  --root-color: #1f2328;
  --top-background-color: #f6f8fa;
  --top-border-color: #d1d9e0;
  --panel-background-color: #f6f8fa;
  --modal-background-color: #ffffff;
  --modal-help-background-color: #f6f8fa;
  --modal-help-color: #59636e;
  --modal-hint-background-color: #0969da;
  --modal-hint-color: #ffffff;
  --modal-hint-inactive-background-color: #818b981f;
  --modal-hint-inactive-color: #59636e;
  --action-button-color: #59636e;
  --action-button-hover-color: #0969da;
  --action-button-active-color: #0969da;
  --progress-index-color: #0969da;
  --editor-caret-color: #1f2328;
  --editor-selection-background-color: #0969da33;
  --editor-heading-color: #1f2328;
  --editor-list-bullet-color: #59636e;
  --editor-hashtag-background-color: #ddf4ff;
  --editor-hashtag-color: #0969da;
  --editor-hashtag-border-color: #0969da33;
  --editor-wiki-link-page-background-color: transparent;
  --editor-code-color: #1f2328;
  --editor-code-background-color: #818b981f;
  --editor-blockquote-background-color: transparent;
  --editor-blockquote-color: #59636e;
  --editor-blockquote-border-color: #d1d9e0;
  --editor-table-head-background-color: #f6f8fa;
  --editor-table-head-color: #1f2328;
  --editor-table-even-background-color: #f6f8fa;
  --editor-frontmatter-background-color: #f6f8fa;
  --editor-frontmatter-marker-color: #59636e;
  --editor-widget-background-color: #f6f8fa;
  --editor-command-button-background-color: #f6f8fa;
  --editor-command-button-border-color: #d1d9e0;
  --editor-struct-color: #cf222e;
  --editor-task-state-color: #9a6700;
  --editor-code-comment-color: #59636e;
  --editor-code-variable-color: #953800;
  --editor-code-typename-color: #6639ba;
  --editor-code-string-color: #0a3069;
  --editor-code-number-color: #0550ae;
  --editor-code-atom-color: #0550ae;
}
html[data-theme="dark"] {
  --ui-accent-color: #4493f8;
  --ui-accent-contrast-color: #0d1117;
  --link-color: #4493f8;
  --link-missing-color: #db6d28;
  --link-invalid-color: #ab7df8;
  --meta-color: #ff7b72;
  --meta-subtle-color: #9198a1;
  --subtle-color: #9198a1;
  --subtle-background-color: #656c7633;
  --ui-surface-border-color: #3d444d;
  --root-background-color: #0d1117;
  --root-color: #f0f6fc;
  --top-color: #f0f6fc;
  --top-background-color: #151b23;
  --top-border-color: #3d444d;
  --panel-background-color: #151b23;
  --panel-border-color: #3d444d;
  --bhs-background-color: #0d1117;
  --bhs-border-color: #3d444d;
  --modal-background-color: #151b23;
  --modal-help-background-color: #151b23;
  --modal-help-color: #9198a1;
  --modal-hint-background-color: #1f6feb;
  --modal-hint-color: #ffffff;
  --modal-hint-inactive-background-color: #656c7633;
  --modal-hint-inactive-color: #9198a1;
  --action-button-color: #9198a1;
  --action-button-hover-color: #4493f8;
  --action-button-active-color: #4493f8;
  --progress-index-color: #4493f8;
  --editor-caret-color: #f0f6fc;
  --editor-selection-background-color: #4493f84d;
  --editor-heading-color: #f0f6fc;
  --editor-list-bullet-color: #9198a1;
  --editor-hashtag-background-color: #388bfd1a;
  --editor-hashtag-color: #4493f8;
  --editor-hashtag-border-color: #1f6feb66;
  --editor-wiki-link-page-background-color: transparent;
  --editor-code-color: #f0f6fc;
  --editor-code-background-color: #656c7633;
  --editor-blockquote-background-color: transparent;
  --editor-blockquote-color: #9198a1;
  --editor-blockquote-border-color: #3d444d;
  --editor-table-head-background-color: #151b23;
  --editor-table-head-color: #f0f6fc;
  --editor-table-even-background-color: #151b23;
  --editor-frontmatter-background-color: #151b23;
  --editor-frontmatter-marker-color: #9198a1;
  --editor-widget-background-color: #151b23;
  --editor-command-button-background-color: #151b23;
  --editor-command-button-border-color: #3d444d;
  --editor-struct-color: #ff7b72;
  --editor-task-state-color: #d29922;
  --editor-code-comment-color: #9198a1;
  --editor-code-variable-color: #ffa657;
  --editor-code-typename-color: #d2a8ff;
  --editor-code-string-color: #a5d6ff;
  --editor-code-number-color: #79c0ff;
  --editor-code-atom-color: #79c0ff;
}
```

## Settings

Runs before the standard library (priority 5), so the journal commands never appear. The page tree opens on the left, and the page search (Cmd-K) and notes search (Cmd-Shift-F) open in the same left slot while you search: a sidebar slot shows one view at a time, and closing a search brings the tree back. The table of contents opens on the right. Each browser keeps its own choice once you move or close a panel.

```space-lua
-- priority: 5
config.set("journal.enabled", false)
-- Index every paragraph, not only tagged ones, so the notes search finds body text.
config.set("index.paragraph.all", true)
config.set("view.defaults", {
  ["std.spaceTree"] = { dock = "lhs", open = true },
  ["std.pages"] = { dock = "lhs" },
  ["std.toc"] = { dock = "rhs", open = true },
  -- SilverBullet treats Basic Memory observations as tasks; this list would offer state clicks that erase categories.
  ["std.linkedTasks"] = { open = false },
})
```

## New notes

New notes start with the frontmatter Basic Memory would otherwise insert while you type, which dropped a newline. SilverBullet-only pages and virtual pages get no frontmatter.

```space-lua
agentHub = agentHub or {}

-- Pages the notes .gitignore keeps out of Basic Memory.
local SB_ONLY_PREFIXES = { "Library/", "Repositories/", "Journal/", "Inbox/" }
local SB_ONLY_PAGES = { index = true, CONFIG = true }

function agentHub.isNote(name)
  if SB_ONLY_PAGES[name] then
    return false
  end
  for _, prefix in ipairs(SB_ONLY_PREFIXES) do
    if name:startsWith(prefix) then
      return false
    end
  end
  return true
end

event.listen {
  name = "editor:pageCreating",
  run = function(e)
    local name = e.data.name
    if not agentHub.isNote(name) then
      return nil
    end
    for _, def in pairs(config.get("virtualPages", {})) do
      if name:match(def.pattern) then
        return nil
      end
    end
    local title = name:match("([^/]+)$"):gsub("\"", "\\\"")
    local permalink = "main/" .. string.lower(name):gsub("[%s_]+", "-")
    return {
      text = "---\ntitle: \"" .. title .. "\"\ntype: note\npermalink: " .. permalink .. "\n---\n|^|",
      perm = "rw",
    }
  end,
}
```

## Reading and finding notes

Read-only helpers, nothing is written into the notes:

- A page-info line above every note: last update, word count, reading time, backlinks and the `memory://` URL agents use.
- `Search: Notes` (Cmd-Shift-F) searches headers, observations, list items and paragraphs in the left slot, because SilverBullet has no built-in full-text search.
- `Basic Memory: Copy memory:// Link` and `Navigate: Random Note`.

```space-style
.agent-hub-page-info {
  color: var(--subtle-color);
  font-size: 0.85em;
}
```

```space-lua
-- Blocks may load in any order, so this one creates the table too.
agentHub = agentHub or {}

local WORDS_PER_MINUTE = 200
local SEARCH_MIN_BYTES = 2
local SEARCH_MAX_ROWS = 100

local function pageObject(name)
  local pages = query[[from p = index.pages() where p.name == name limit 1]]
  return pages[1]
end

function agentHub.memoryUrl(name)
  local page = name and pageObject(name)
  if page and page.permalink then
    return "memory://" .. page.permalink
  end
  return nil
end

local function backlinkCount(name)
  local seen, count = {}, 0
  for _, r in ipairs(query[[from r = index.relations() where r.to == name and r.page != name and r.kind != "co-mention"]]) do
    if not seen[r.page] then
      seen[r.page] = true
      count = count + 1
    end
  end
  return count
end

local function wordCount(text)
  local body = text:gsub("^%-%-%-\n.-\n%-%-%-\n", "")
  local count = 0
  for _ in body:gmatch("%S+") do
    count = count + 1
  end
  return count
end

function agentHub.pageInfo()
  local name = editor.getCurrentPage()
  if not name or not agentHub.isNote(name) then
    return nil
  end
  local page = pageObject(name)
  local words = wordCount(editor.getText())
  local parts = {}
  if page and page.lastModified then
    table.insert(parts, "Updated " .. (string.sub(page.lastModified, 1, 16):gsub("T", " ")))
  end
  table.insert(parts, words .. " words")
  table.insert(parts, "~" .. math.max(1, math.ceil(words / WORDS_PER_MINUTE)) .. " min read")
  table.insert(parts, backlinkCount(name) .. " backlinks")
  local url = agentHub.memoryUrl(name)
  if url then
    table.insert(parts, "`" .. url .. "`")
  end
  return widget.new {
    markdown = table.concat(parts, " · "),
    cssClasses = { "agent-hub-page-info" },
  }
end

view.define {
  name = "agentHub.pageInfo",
  title = "Page info",
  dock = "page-top",
  supportedDocks = { "page-top", "page-bottom" },
  frame = "minimal",
  refreshOn = { "navigate", "index" },
  content = function()
    return agentHub.pageInfo()
  end,
}

local function addMatch(rows, obj, text, needle)
  if #rows >= SEARCH_MAX_ROWS or not text or not obj.page or not agentHub.isNote(obj.page) then
    return
  end
  if string.find(string.lower(text), needle, 1, true) then
    table.insert(rows, { page = obj.page, excerpt = text, ref = obj.ref })
  end
end

-- Tags live in their own field and only sometimes stay in the text, so add the missing ones back.
local function withTags(text, tags)
  if not text or not tags then
    return text
  end
  local lower = string.lower(text)
  for _, tag in ipairs(tags) do
    if not string.find(lower, "#" .. string.lower(tag), 1, true) then
      text = text .. " #" .. tag
    end
  end
  return text
end

function agentHub.searchRows(phrase)
  local needle = string.lower(phrase or "")
  if #needle < SEARCH_MIN_BYTES then
    return {}
  end
  local rows = {}
  for _, h in ipairs(query[[from h = index.headers()]]) do
    addMatch(rows, h, h.name, needle)
  end
  for _, t in ipairs(query[[from t = index.tasks()]]) do
    addMatch(rows, t, withTags("[" .. (t.state or "") .. "] " .. t.name, t.tags), needle)
  end
  for _, i in ipairs(query[[from i = index.items()]]) do
    addMatch(rows, i, withTags(i.text, i.tags), needle)
  end
  for _, p in ipairs(query[[from p = index.paragraphs()]]) do
    addMatch(rows, p, p.text, needle)
  end
  return rows
end

view.define {
  name = "agentHub.search",
  title = "Search notes",
  label = "Search",
  placeholder = "Text in notes",
  helpText = "Headers, observations, list items and paragraphs of Basic Memory notes. Paragraphs missing? Run Space: Reindex once in this browser.",
  command = "Search: Notes",
  key = "Ctrl-Shift-f",
  mac = "Cmd-Shift-f",
  dock = "lhs",
  supportedDocks = { "lhs", "rhs", "modal" },
  search = "source",
  source = function(ctx)
    return agentHub.searchRows(ctx.phrase)
  end,
  presentation = {
    mode = "list",
    row = {
      primary = "page",
      description = function(row)
        return { text = row.excerpt }
      end,
    },
  },
  onSelect = function(row)
    editor.navigate(row.ref)
  end,
}

command.define {
  name = "Basic Memory: Copy memory:// Link",
  run = function()
    local url = agentHub.memoryUrl(editor.getCurrentPage())
    if not url then
      editor.flashNotification("This page has no Basic Memory permalink", "warning")
      return
    end
    editor.copyToClipboard(url)
    editor.flashNotification("Copied " .. url)
  end,
}

command.define {
  name = "Navigate: Random Note",
  run = function()
    local notes = {}
    for _, p in ipairs(query[[from p = index.pages()]]) do
      if agentHub.isNote(p.name) then
        table.insert(notes, p.name)
      end
    end
    if #notes > 0 then
      editor.navigate(notes[math.random(#notes)])
    end
  end,
}
```

## Dashboard

`agentHub.dashboard()` renders the [[index]] page: recently changed notes, top folders, Basic Memory observations by category (SilverBullet indexes `- [decision] ...` as a task whose state is the category) and tags.

```space-lua
-- Blocks may load in any order, so this one creates the table too.
agentHub = agentHub or {}

local RECENT_NOTES = 10
local NOTES_PER_FOLDER = 3
local OBSERVATIONS_PER_CATEGORY = 10

local function bullets(lines, empty)
  if #lines == 0 then
    return "_" .. empty .. "_"
  end
  return table.concat(lines, "\n")
end

local function shortLink(name)
  return "[[" .. name .. "|" .. name:match("([^/]+)$") .. "]]"
end

local function recentNotes()
  local lines = {}
  for _, p in ipairs(query[[from p = index.pages() order by p.lastModified desc]]) do
    if agentHub.isNote(p.name) then
      table.insert(lines, "- [[" .. p.name .. "]]")
      if #lines == RECENT_NOTES then
        break
      end
    end
  end
  return bullets(lines, "No notes yet")
end

local function folders()
  local byFolder, names = {}, {}
  for _, p in ipairs(query[[from p = index.pages() order by p.lastModified desc]]) do
    local folder = p.name:match("^([^/]+)/")
    if folder and agentHub.isNote(p.name) then
      local entry = byFolder[folder]
      if not entry then
        entry = { count = 0, links = {} }
        byFolder[folder] = entry
        table.insert(names, folder)
      end
      entry.count = entry.count + 1
      if #entry.links < NOTES_PER_FOLDER then
        table.insert(entry.links, shortLink(p.name))
      end
    end
  end
  table.sort(names)
  local lines = {}
  for _, folder in ipairs(names) do
    local entry = byFolder[folder]
    table.insert(lines, "- **" .. folder .. "** (" .. entry.count .. "): " .. table.concat(entry.links, ", "))
  end
  return bullets(lines, "No folders yet")
end

local function observations(category)
  local lines = {}
  for _, t in ipairs(query[[from t = index.tasks() order by t.page]]) do
    if t.state == category and agentHub.isNote(t.page) then
      table.insert(lines, "- " .. t.name .. " (" .. shortLink(t.page) .. ")")
      if #lines == OBSERVATIONS_PER_CATEGORY then
        break
      end
    end
  end
  return bullets(lines, "None")
end

local function tagList()
  local counts, names = {}, {}
  for _, t in ipairs(query[[from t = index.tags()]]) do
    if t.page and agentHub.isNote(t.page) then
      if not counts[t.name] then
        counts[t.name] = 0
        table.insert(names, t.name)
      end
      counts[t.name] = counts[t.name] + 1
    end
  end
  table.sort(names, function(a, b)
    if counts[a] ~= counts[b] then
      return counts[a] > counts[b]
    end
    return a < b
  end)
  local items = {}
  for _, name in ipairs(names) do
    table.insert(items, "- #" .. name .. " (" .. counts[name] .. ")")
  end
  return bullets(items, "No tags yet")
end

function agentHub.dashboard()
  return table.concat({
    "## Recently changed", recentNotes(), "",
    "## Folders", folders(), "",
    "## Decisions", observations("decision"), "",
    "## Risks", observations("risk"), "",
    "## Open questions", observations("question"), "",
    "## Tags", tagList(), "",
    "## Maintenance", "[[Library/Std/Pages/Maintenance|Broken and ambiguous links]]",
  }, "\n")
end
```
