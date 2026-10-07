# Native build and install of FormalShell, shared by the Arch and Debian
# packages. It mirrors what nix/package.nix, nix/hm-module.nix and
# nix/nixos-module.nix install; the watchdog and power poll scripts are the
# same files the Nix build substitutes, so the two cannot drift.
#
#   make -C packaging
#   make -C packaging install DESTDIR=pkgdir PREFIX=/usr LUCIDE_TTF=lucide.ttf
#
# The build is offline: the distro build fetches the workspace's crates into
# CARGO_HOME beforehand (`cargo fetch --locked` in crates/), and cargo runs
# with --frozen here.
#
# LUCIDE_TTF is lucide-font/lucide.ttf out of the release zip nix/lucide-font.nix
# pins. PAM picks the include syntax of pam/formalshell-lock.<PAM>: arch
# (system-auth) or debian (common-auth, common-account).
#
# Units ship with presets and are never enabled here; enabling them is the
# distro package's call.

PREFIX ?= /usr/local
SYSCONFDIR ?= /etc
BINDIR ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share
SHAREDIR ?= $(DATADIR)/formalshell
LIBEXECDIR ?= $(PREFIX)/lib/formalshell
SYSTEMDUSERUNITDIR ?= $(PREFIX)/lib/systemd/user
SYSTEMDUNITDIR ?= $(PREFIX)/lib/systemd/system
FONTDIR ?= $(DATADIR)/fonts/formalshell

CARGO ?= cargo
TIMEOUT ?= /usr/bin/timeout
SYSTEMCTL ?= /usr/bin/systemctl
PAM ?= arch
LUCIDE_TTF ?=

SRC := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
PKG := $(SRC)/packaging
TARGET_DIR ?= $(SRC)/crates/target
RELEASE := $(TARGET_DIR)/release

SUBST = sed -e 's|@SHAREDIR@|$(SHAREDIR)|g' -e 's|@FONTDIR@|$(FONTDIR)|g' \
	-e 's|@BINDIR@|$(BINDIR)|g' -e 's|@LIBEXECDIR@|$(LIBEXECDIR)|g' \
	-e 's|@IPC@|$(BINDIR)/formalshell-ipc|g' \
	-e 's|@TIMEOUT@|$(TIMEOUT)|g' -e 's|@SYSTEMCTL@|$(SYSTEMCTL)|g'

SCRIPTS = formalshell formalshell-watchdog
USER_UNITS = formalshell.service formalshell-watchdog.service

.PHONY: all install
all:
	cd $(SRC)/crates && CARGO_TARGET_DIR=$(TARGET_DIR) \
		$(CARGO) build --frozen --release --package formalshell-rs

install:
	@test -n "$(LUCIDE_TTF)" || { echo "LUCIDE_TTF is not set" >&2; exit 1; }
	@test -f "$(PKG)/pam/formalshell-lock.$(PAM)" || { echo "PAM must be arch or debian" >&2; exit 1; }
	@test -x "$(RELEASE)/formalshell-rs" || { echo "no $(RELEASE)/formalshell-rs; run make first" >&2; exit 1; }
	install -Dm755 $(RELEASE)/formalshell-rs $(DESTDIR)$(LIBEXECDIR)/formalshell-rs
	install -Dm755 $(RELEASE)/formalshell-ipc $(DESTDIR)$(BINDIR)/formalshell-ipc
	install -d $(DESTDIR)$(SHAREDIR)
	cp -R $(SRC)/shell/Theme/templates $(DESTDIR)$(SHAREDIR)/templates
	cp -R $(SRC)/branding $(DESTDIR)$(SHAREDIR)/branding
	install -d $(DESTDIR)$(SHAREDIR)/examples
	cp -R $(SRC)/docs/examples/. $(DESTDIR)$(SHAREDIR)/examples/
	chmod -R u=rwX,go=rX $(DESTDIR)$(SHAREDIR)
	for s in $(SCRIPTS); do \
		$(SUBST) $(PKG)/$$s.in > $(DESTDIR)$(BINDIR)/$$s && chmod 755 $(DESTDIR)$(BINDIR)/$$s || exit 1; \
	done
	{ echo '#!/bin/sh'; cat $(PKG)/formalshell-power-poll.sh; } > $(DESTDIR)$(LIBEXECDIR)/formalshell-power-poll
	chmod 755 $(DESTDIR)$(LIBEXECDIR)/formalshell-power-poll
	install -d $(DESTDIR)$(SYSTEMDUSERUNITDIR) $(DESTDIR)$(SYSTEMDUNITDIR)
	for u in $(USER_UNITS); do \
		$(SUBST) $(PKG)/systemd/$$u.in > $(DESTDIR)$(SYSTEMDUSERUNITDIR)/$$u && chmod 644 $(DESTDIR)$(SYSTEMDUSERUNITDIR)/$$u || exit 1; \
	done
	install -m644 $(PKG)/systemd/formalshell-watchdog.timer $(DESTDIR)$(SYSTEMDUSERUNITDIR)/
	$(SUBST) $(PKG)/systemd/formalshell-power-poll.service.in > $(DESTDIR)$(SYSTEMDUNITDIR)/formalshell-power-poll.service
	chmod 644 $(DESTDIR)$(SYSTEMDUNITDIR)/formalshell-power-poll.service
	install -Dm644 $(PKG)/systemd/90-formalshell-user.preset $(DESTDIR)$(PREFIX)/lib/systemd/user-preset/90-formalshell.preset
	install -Dm644 $(PKG)/systemd/90-formalshell-system.preset $(DESTDIR)$(PREFIX)/lib/systemd/system-preset/90-formalshell.preset
	install -Dm644 $(PKG)/pam/formalshell-lock.$(PAM) $(DESTDIR)$(SYSCONFDIR)/pam.d/formalshell-lock
	install -Dm644 $(PKG)/geoclue-formalshell.conf $(DESTDIR)$(SYSCONFDIR)/geoclue/conf.d/formalshell.conf
	install -Dm644 $(LUCIDE_TTF) $(DESTDIR)$(FONTDIR)/lucide.ttf
