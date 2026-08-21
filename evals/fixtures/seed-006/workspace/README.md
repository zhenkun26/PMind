# Admin Console Selection Fixture

This is a dependency-free snapshot of a larger React/TypeScript admin console.
The source files are representative excerpts; `metrics.json` records the
frozen full-codebase measurements used by the calibration case.

Do not install packages or start a rewrite. The expected deliverable is defined
in `CONTRACT.md`.

Run the snapshot consistency check with:

```sh
ruby test/snapshot_test.rb
```
