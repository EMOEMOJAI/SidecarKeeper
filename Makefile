# Local build check (there is no CI: the project only builds on macOS).
SWIFTC ?= swiftc
BUILD  ?= build

.PHONY: build test check install uninstall clean

build: $(BUILD)/sidecar-keeper

$(BUILD)/sidecar-keeper: Sources/SidecarKeeper/main.swift
	@mkdir -p $(BUILD)
	$(SWIFTC) -O -warnings-as-errors -framework AppKit $< -o $@

# Behaviour tests against a fake SidecarLauncher; no iPad involved (~40 s).
test: build
	tests/run.sh $(BUILD)/sidecar-keeper

# Run before every push.
check: build test
	bash -n install.sh uninstall.sh tests/run.sh tests/fake-launcher.sh assets/render.sh
	@if command -v shellcheck >/dev/null; then shellcheck install.sh uninstall.sh tests/*.sh assets/render.sh && echo "shellcheck ok"; else echo "shellcheck not installed, skipped"; fi
	@plutil -lint launchd/com.sidecarkeeper.plist.template >/dev/null && echo "template ok"

install:
	./install.sh $(INSTALL_ARGS)

uninstall:
	./uninstall.sh

clean:
	rm -rf $(BUILD)
