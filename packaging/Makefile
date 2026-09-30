# Native install of FormalShell against the distro's quickshell (>= 0.3.1)
# and Qt, shared by the Arch and Debian packages. It mirrors what
# nix/package.nix, nix/hm-module.nix and nix/nixos-module.nix install; the
# watchdog and power poll scripts are the same files the
# Nix build substitutes, so the two cannot drift.
#
#   make -C packaging install DESTDIR=pkgdir PREFIX=/usr LUCIDE_TTF=lucide.ttf
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

# Arch and Debian both ship /usr/bin/quickshell with a qs symlink beside it.
QS ?= /usr/bin/quickshell
QSB ?= $(firstword $(wildcard /usr/lib/qt6/bin/qsb /usr/lib/qt6/libexec/qsb /usr/lib64/qt6/bin/qsb) qsb)
TIMEOUT ?= /usr/bin/timeout
SYSTEMCTL ?= /usr/bin/systemctl
PAM ?= arch
LUCIDE_TTF ?=

SRC := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)
PKG := $(SRC)/packaging

SUBST = sed -e 's|@QS@|$(QS)|g' -e 's|@SHAREDIR@|$(SHAREDIR)|g' \
	-e 's|@BINDIR@|$(BINDIR)|g' -e 's|@LIBEXECDIR@|$(LIBEXECDIR)|g' \
	-e 's|@TIMEOUT@|$(TIMEOUT)|g' -e 's|@SYSTEMCTL@|$(SYSTEMCTL)|g'

SCRIPTS = formalshell formalshell-ipc formalshell-watchdog
USER_UNITS = formalshell.service formalshell-watchdog.service

.PHONY: all install
all:
	@echo "nothing to build; run make install" >&2

install:
	@test -n "$(LUCIDE_TTF)" || { echo "LUCIDE_TTF is not set" >&2; exit 1; }
	@test -f "$(PKG)/pam/formalshell-lock.$(PAM)" || { echo "PAM must be arch or debian" >&2; exit 1; }
	install -d $(DESTDIR)$(SHAREDIR)
	cp -R $(SRC)/shell/. $(DESTDIR)$(SHAREDIR)/
	find $(DESTDIR)$(SHAREDIR) \( -name '*.qmlc' -o -name .qmlls.ini \) -delete
# A ShaderEffect loads its shaders as .qsb, never as GLSL source.
	find $(DESTDIR)$(SHAREDIR) -name '*.frag' -exec $(QSB) --qt6 -o {}.qsb {} \;
	cp -R $(SRC)/branding $(DESTDIR)$(SHAREDIR)/branding
	install -d $(DESTDIR)$(SHAREDIR)/examples
	cp -R $(SRC)/docs/examples/. $(DESTDIR)$(SHAREDIR)/examples/
	chmod -R u=rwX,go=rX $(DESTDIR)$(SHAREDIR)
	install -d $(DESTDIR)$(BINDIR)
	for s in $(SCRIPTS); do \
		$(SUBST) $(PKG)/$$s.in > $(DESTDIR)$(BINDIR)/$$s && chmod 755 $(DESTDIR)$(BINDIR)/$$s || exit 1; \
	done
	install -d $(DESTDIR)$(LIBEXECDIR)
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
