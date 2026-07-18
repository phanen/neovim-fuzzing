#!/usr/bin/env -S nvim -l
-- bin/write-json-report.lua -- emit report.json for a daily-fuzz run.
-- Bash (scripts/daily-fuzz.sh) gathers per-crash metadata into a
-- pipe-delimited stdin stream; this script folds it into the final
-- report.json schema (a single jq-able object).
--
-- Stdin format (one per line, pipe-delimited):
--   <crash-id>|<kind>|<rounds>|<size_bytes>|<asan_lines>|<crash_file_rel>
--   <crash-id>         sanitized AFL crash filename (id_000000_sig_06_...)
--   <kind>             "min" | "full" | "raw"  (best available repro)
--   <rounds>           min=bisected floor, full=captured ROUNDS, raw=0
--   <size_bytes>       bytes of the chosen repro (or crash.bin for raw)
--   <asan_lines>       count of AddressSanitizer lines in verify.err
--   <crash_file_rel>   path of AFL's saved crash, repo-root-relative
--
-- Required args:
--   --report-dir PATH         where report.json lands (= $REPORT_DIR)
--   --crashes-dir PATH        repo-root-relative afl-findings/<date>/default/crashes
--   --fuzz-log PATH           $REPORT_DIR/fuzz.log (gitignored)
--   --root PATH               repo root (only used to anchor the
--                              binary sha256 lookups; never emitted)
--   --date YYYY-MM-DD_HHMMSS  UTC run-start marker (also the dir suffix)
--   --ts ISO8601              UTC timestamp of run start
--   --duration SEC            total fuzzing wall-clock seconds (string with 's')
--   --capture-rounds N        ROUNDS env used for the AFL session
--   --asan-options STR        ASAN_OPTIONS string used by run_fuzz
--                              (mirrored into repro.lua footers and the
--                              runtime block so reproductions match)
--   --nvim-bin PATH           path to the afl-built nvim binary
--                              (default deps/neovim/build-afl/bin/nvim)
--   --afl-bin PATH            path to the patched afl-fuzz binary
--                              (default /usr/local/bin/afl-fuzz)
--   --patches-dir PATH        repo-root-relative patches/ dir
--                              (default patches/)
--
-- Output: JSON object on stdout. Bash redirects to report.json.

local args = arg or {}
local function getopt(name, default)
  for i = 1, #args do
    if args[i] == name then return args[i + 1] end
  end
  return default
end

local REPORT_DIR    = getopt('--report-dir')
local CRASHES_DIR   = getopt('--crashes-dir')
local FUZZ_LOG      = getopt('--fuzz-log')
local ROOT          = getopt('--root')
local DATE          = getopt('--date')
local TS            = getopt('--ts')
local DURATION      = getopt('--duration')
local CAPTURE_ROUNDS = tonumber(getopt('--capture-rounds')) or 25
local ASAN_OPTIONS  = getopt('--asan-options') or ''
local NVIM_BIN      = getopt('--nvim-bin',
  ROOT .. '/deps/neovim/build-afl/bin/nvim')
local AFL_BIN       = getopt('--afl-bin', '/usr/local/bin/afl-fuzz')
local PATCHES_DIR   = getopt('--patches-dir', 'patches')

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

local function trim(s) return (vim.trim(s or '')) end

local function sh(cmd, opts)
  local r = vim.system(cmd, vim.tbl_extend('keep', { text = true }, opts or {})):wait()
  return { code = r.code, stdout = r.stdout or '', stderr = r.stderr or '' }
end

local function exists(p) return vim.uv.fs_stat(p) ~= nil end

local function count_asan_in(path)
  if not exists(path) then return 0 end
  local n = 0
  for line in io.lines(path) do
    if line:find('AddressSanitizer', 1, true) then n = n + 1 end
  end
  return n
end

-- SHA256 hex digest of a file's contents. Empty string if the file
-- is missing (don't blow up the report on a missing binary).
local function sha256_of(p)
  if not exists(p) then return '' end
  local r = sh({ 'sha256sum', p })
  return (r.stdout:match('(%x+)') or '')
end

-- Take the first line of a version-style command's output (e.g.
-- `nvim --version`, `afl-fuzz --version`). Empty string on failure.
local function first_line(cmd)
  local r = sh(cmd)
  if r.code ~= 0 or r.stdout == '' then return '' end
  return (r.stdout:match('([^\n]*)') or '')
end

-- ---------------------------------------------------------------------------
-- runtime block: nvim + afl_fuzz build fingerprints
-- ---------------------------------------------------------------------------

local nvim_branch = trim(sh({ 'git', '-C', ROOT .. '/deps/neovim',
  'symbolic-ref', '--short', 'HEAD' }).stdout)
local nvim_rev    = trim(sh({ 'git', '-C', ROOT .. '/deps/neovim',
  'rev-parse', '--short', 'HEAD' }).stdout)
local our_rev    = trim(sh({ 'git', '-C', ROOT, 'rev-parse',
  '--short', 'HEAD' }).stdout)

-- Use `git describe` for the version line: nvim's own --version
-- triggers LeakSanitizer on first invocation under our ASAN build,
-- and the embedded version string is what we actually want anyway.
local nvim_version = trim(sh({ 'git', '-C', ROOT .. '/deps/neovim',
  'describe', '--tags', '--dirty', '--long' }).stdout)
if nvim_version == '' then
  -- git describe fails when there are no tags (e.g. shallow clone).
  -- Fall back to commit-only.
  nvim_version = trim(sh({ 'git', '-C', ROOT .. '/deps/neovim',
    'rev-parse', 'HEAD' }).stdout)
end
local afl_version = first_line({ AFL_BIN, '--version' })

-- patches: relative paths under PATCHES_DIR (resolved against ROOT).
local patches = {}
if vim.fn.isdirectory(PATCHES_DIR) == 1 then
  for _, name in ipairs(vim.fn.readdir(PATCHES_DIR)) do
    if name:match('%.patch$') or name:match('%.diff$') then
      local rel = PATCHES_DIR .. '/' .. name
      patches[#patches + 1] = {
        path = rel,
        sha256 = sha256_of(ROOT .. '/' .. rel),
      }
    end
  end
end
table.sort(patches, function(a, b) return a.path < b.path end)

local runtime = {
  nvim = {
    branch = nvim_branch ~= '' and nvim_branch or 'detached',
    rev = nvim_rev ~= '' and nvim_rev or 'unknown',
    version_line = nvim_version,
    binary_sha256 = sha256_of(NVIM_BIN),
  },
  afl_fuzz = {
    version = afl_version,
    patches = patches,
    binary_sha256 = sha256_of(AFL_BIN),
  },
  asan_options = ASAN_OPTIONS,
  capture_rounds = CAPTURE_ROUNDS,
}

-- ---------------------------------------------------------------------------
-- Parse stdin: pipe-delimited entries
-- ---------------------------------------------------------------------------

local entries = {}
for line in io.lines() do
  if line ~= '' then
    local id, kind, rounds, sz, asan, crash_file = line:match(
      '^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$')
    if id then
      entries[#entries + 1] = {
        id = id,
        kind = kind,
        rounds = tonumber(rounds) or 0,
        size_bytes = tonumber(sz) or 0,
        asan_lines = tonumber(asan) or 0,
        crash_file = crash_file or '',
      }
    end
  end
end

-- ---------------------------------------------------------------------------
-- Aggregate counts
-- ---------------------------------------------------------------------------

local n_repros = 0
local asan_in_repros = 0
for _, e in ipairs(entries) do
  if e.kind ~= 'raw' then n_repros = n_repros + 1 end
  asan_in_repros = asan_in_repros + e.asan_lines
end

local fuzz_log_lines = count_asan_in(FUZZ_LOG)

local saved_crashes = 0
if vim.fn.isdirectory(CRASHES_DIR) == 1 then
  for _, name in ipairs(vim.fn.readdir(CRASHES_DIR)) do
    if not name:match('%.repro%.lua$') and not name:match('%.min%.lua$') then
      saved_crashes = saved_crashes + 1
    end
  end
end

-- ---------------------------------------------------------------------------
-- Emit
-- ---------------------------------------------------------------------------

local report = {
  date = DATE,
  ts = TS,
  duration = DURATION,
  runtime = runtime,
  saved_crashes = saved_crashes,
  reporos_generated = n_repros,
  asan_in_repros = asan_in_repros,
  reporos = entries,
  repo_rev = our_rev,
}

-- Pretty-print with 2-space indent so the JSON is diff-friendly in
-- the bot's auto-commit (otherwise everything would collapse onto one
-- line and every crash delta would touch the whole file).
io.write(vim.json.encode(report, { indent = '  ' }) .. '\n')