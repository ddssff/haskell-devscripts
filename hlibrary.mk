# -*- mode: makefile -*-
# Copyright 2008 Kari Pahula <kaol@debian.org>
# Description: A class for Haskell library packages
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2, or (at
# your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
# 02111-1307 USA.

CABAL_PACKAGE = $(shell cat *.cabal |\
 perl -ne 'if (/^name:\s*(.*)$$/i) {$$_ = $$1; tr/A-Z/a-z/; print; exit 0;}')

ENABLE_PROFILING = $(shell egrep -qe '^Package: libghc6-.*-prof$$' debian/control && echo --enable-library-profiling; exit 0)

DEB_COMPRESS_EXCLUDE += .haddock

# TODO:
# - some of this would probably be useful for generic Haskell programs,
#   not just libraries
# - provide more hooks
# - get this included in the cdbs package once this gets mature enough (maybe?)

# For now, you can find the newest version in
# http://people.debian.org/~kaol/repos/hlibrary/

DEB_SETUP_BIN_NAME ?= debian/hlibrary.setup
DEB_HADDOCK_HTML_DIR ?= /usr/share/doc/libghc6-$(CABAL_PACKAGE)-doc/html/

# most likely you don't need to touch this one
DEB_HADDOCK_DIR ?= /usr/lib/ghc6-doc/haddock/

clean::
	test ! -e $(DEB_SETUP_BIN_NAME) || $(DEB_SETUP_BIN_NAME) clean
	rm -rf dist dist-ghc6 dist-hugs $(DEB_SETUP_BIN_NAME) Setup.hi Setup.ho Setup.o .*config*
	rm -f build-ghc6-stamp build-hugs-stamp
	rm -rf debian/tmp-inst-ghc6

$(DEB_SETUP_BIN_NAME):
	if test ! -e Setup.lhs -a ! -e Setup.hs; then echo "No setup script found!"; exit 1; fi
	for setup in Setup.lhs Setup.hs; do if test -e $$setup; then ghc6 -package Cabal $$setup -o $(DEB_SETUP_BIN_NAME); exit 0; fi; done

dist-ghc6: $(DEB_SETUP_BIN_NAME)
	$(DEB_SETUP_BIN_NAME) configure --ghc -v2 \
		--prefix=/usr --libdir=/usr/lib/haskell-packages/ghc6/lib \
		--interfacedir=$(DEB_HADDOCK_DIR) \
		--htmldir=$(DEB_HADDOCK_HTML_DIR) $(ENABLE_PROFILING) \
		$(DEB_SETUP_GHC6_CONFIGURE_ARGS)
	mv dist dist-ghc6

build-ghc6-stamp: dist-ghc6
	mv dist-ghc6 dist
	$(DEB_SETUP_BIN_NAME) build
	mv dist dist-ghc6
	touch build-ghc6-stamp

build/libghc6-$(CABAL_PACKAGE)-prof build/libghc6-$(CABAL_PACKAGE)-dev:: build-ghc6-stamp

# Provide two alternate names for the -doc package
build/haskell-$(CABAL_PACKAGE)-doc build/libghc6-$(CABAL_PACKAGE)-doc:: dist-ghc6
	mv dist-ghc6 dist
# The build target may be called by buildds without having the
# build-depends-indep installed
	[ ! -x /usr/bin/haddock ] || $(DEB_SETUP_BIN_NAME) haddock $(DEB_HADDOCK_OPTS)
	mv dist dist-ghc6

dist-hugs: $(DEB_SETUP_BIN_NAME)
	$(DEB_SETUP_BIN_NAME) configure --hugs --prefix=/usr -v2
	mv dist dist-hugs

build/libhugs-$(CABAL_PACKAGE):: dist-hugs
	mv dist-hugs dist
	$(DEB_SETUP_BIN_NAME) build $(DEB_SETUP_HUGS_CONFIGURE_ARGS)
	mv dist dist-hugs

debian/tmp-inst-ghc6: $(DEB_SETUP_BIN_NAME)
	mv dist-ghc6 dist
	$(DEB_SETUP_BIN_NAME) copy --destdir=debian/tmp-inst-ghc6
	mv dist dist-ghc6

install/libghc6-$(CABAL_PACKAGE)-dev:: debian/tmp-inst-ghc6
	mv dist-ghc6 dist
	cd debian/tmp-inst-ghc6 ; find usr/lib/haskell-packages/ghc6/lib/ \
		-name "*[^p].a" -o -name "*.o" -o -name "*.hi" \
		-exec install -Dm 644 '{}' ../$(notdir $@)/'{}' ';'
	dh_haskell_prep -p$(notdir $@)
	cp dist/installed-pkg-config \
		debian/$(notdir $@)/usr/lib/haskell-packages/ghc6/lib/*/
	dh_haskell_depends -p$(notdir $@)
	mv dist dist-ghc6

install/libghc6-$(CABAL_PACKAGE)-prof:: debian/tmp-inst-ghc6 install/libghc6-$(CABAL_PACKAGE)-dev
	mv dist-ghc6 dist
	cd debian/tmp-inst-ghc6 ; find usr/lib/haskell-packages/ghc6/lib/ \
		-name "*_p.a" -o -name "*.p_hi" \
		-exec install -Dm 644 '{}' ../$(notdir $@)/'{}' ';'
	dh_haskell_prep -p$(notdir $@)
	dh_haskell_depends -p$(notdir $@)
	mv dist dist-ghc6

install/haskell-$(CABAL_PACKAGE)-doc install/libghc6-$(CABAL_PACKAGE)-doc:: debian/tmp-inst-ghc6
	mv dist-ghc6 dist
	mkdir -p debian/$(notdir $@)/$(DEB_HADDOCK_HTML_DIR)
	cp -r debian/tmp-inst-ghc6/$(DEB_HADDOCK_HTML_DIR)/* \
		debian/$(notdir $@)/$(DEB_HADDOCK_HTML_DIR)
	mkdir -p debian/$(notdir $@)/$(DEB_HADDOCK_DIR)
	cp -r debian/tmp-inst-ghc6/$(DEB_HADDOCK_DIR)/* \
		debian/$(notdir $@)/$(DEB_HADDOCK_DIR)
	dh_haskell_depends -p$(notdir $@)
	mv dist dist-ghc6

install/libhugs-$(CABAL_PACKAGE):: $(DEB_SETUP_BIN_NAME)
	mv dist-hugs dist
	$(DEB_SETUP_BIN_NAME) copy --destdir=debian/libhugs-$(CABAL_PACKAGE)
	rm -rf debian/libhugs-$(CABAL_PACKAGE)/usr/share/doc/*
	dh_haskell_prep -plibhugs-$(CABAL_PACKAGE)
	mv dist dist-hugs
