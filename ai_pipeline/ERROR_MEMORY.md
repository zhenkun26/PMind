# Error Memory

## 2026-08-21 — Bootstrap PMind agent workflow

- [2026-08-21T17:16:30+08:00] install selected skills environment: referenced a nonexistent bundled Python path, fix: resolve and use `/Library/Frameworks/Python.framework/Versions/3.13/bin/python3`, prevention: run `command -v python3` before invoking repository-external helper scripts
- [2026-08-21T17:16:52+08:00] install selected skills transport: Python ZIP download failed CA certificate verification before writing destination files, fix: use the installer's supported `--method git` transport, prevention: prefer the already-verified Git transport in this workspace
- [2026-08-21T17:21:41+08:00] validate selected skills environment: system Python lacked the validator's PyYAML dependency, fix: resolve and reuse the read-only bundled workspace Python before considering any install, prevention: load workspace dependencies before running bundled validation scripts with non-stdlib imports
- [2026-08-21T17:22:04+08:00] validate selected skills environment: bundled workspace Python also lacked PyYAML, fix: stop Python retries, inspect `quick_validate.py`, and run an equivalent Ruby YAML validation, prevention: probe the required import once before selecting a Python runtime and keep a dependency-free fallback
- [2026-08-21T17:23:21+08:00] validate selected skills references: strict link and dependency checks treated three example context links and a `$skill-name` syntax placeholder as real targets, fix: express examples and syntax without fake resolvable targets, prevention: keep template examples visually distinct from live repository links and concrete Skill references
