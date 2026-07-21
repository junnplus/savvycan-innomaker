BUILD_DIR ?= build
QT_PREFIX ?= /opt/homebrew/opt/qt@5
SAVVYCAN_APP ?=
JOBS ?= 4

.PHONY: all configure clean distclean

all: configure
	cmake --build "$(BUILD_DIR)" -j"$(JOBS)"

configure: clean
	cmake -S . -B "$(BUILD_DIR)" \
		-DCMAKE_PREFIX_PATH="$(QT_PREFIX)" \
		$(if $(SAVVYCAN_APP),-DSAVVYCAN_APP="$(SAVVYCAN_APP)",)

clean:
	rm -rf "$(BUILD_DIR)"

distclean: clean
