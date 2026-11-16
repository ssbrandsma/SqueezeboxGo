# stock/go/ — RETIRED

The `install-squeezebox-go.sh` / `uninstall-squeezebox-go.sh` scripts that
lived here installed a superseded provisional layout and were removed on
2026-11-16 (they would regress the entry script + icon).

The supported installer is the device ZIP built by
`squeezebox-go/pack.sh` — see `squeezebox-go/INSTALL.md`. The reversible
`stock/bundle/` scripts (install/run-jive/restore) remain for manual
SSH-driven PoC work.
