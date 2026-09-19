# Local build check (there is no CI: the project only builds on macOS).
SWIFTC ?= swiftc
BUILD  ?= build

.PHONY: build test check package install uninstall clean

build: $(BUILD)/sidecar-keeper

$(BUILD)/sidecar-keeper: Sources/SidecarKeeper/main.swift
	@mkdir -p $(BUILD)
	$(SWIFTC) -O -warnings-as-errors -framework AppKit $< -o $@

# Behaviour tests against a fake SidecarLauncher; no iPad involved (~40 s).
test: build
	tests/run.sh $(BUILD)/sidecar-keeper

# Run before every push.
check: build test
	bash -n install.sh uninstall.sh tests/run.sh tests/fake-launcher.sh assets/render.sh scripts/package.sh
	@if command -v shellcheck >/dev/null; then shellcheck -S style install.sh uninstall.sh tests/*.sh assets/render.sh scripts/package.sh && echo "shellcheck ok"; else echo "shellcheck not installed, skipped"; fi
	@plutil -lint launchd/com.sidecarkeeper.plist.template >/dev/null && echo "template ok"
	@python3 scripts/check-links.py

# Release bundle with prebuilt universal binaries, in dist/.
package:
	scripts/package.sh

install:
	./install.sh $(INSTALL_ARGS)

uninstall:
	./uninstall.sh

clean:
	rm -rf $(BUILD) dist
