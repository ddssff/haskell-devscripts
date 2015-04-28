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

export GREP_OPTIONS :=

# DH_haskell.sh uses shell features
export SHELL = /bin/bash

# Set a dummy HOME variable upon build. Some build daemons do not set HOME, but
# cabal expects it to be available.
export HOME = /homedoesnotexistatbuildtime

# If we can't figure out which compiler to use from the library
# package names, and DEB_DEFAULT_COMPILER isn't set in debian/rules,
# we can safely assume the desired compiler is ghc.
DEB_DEFAULT_COMPILER ?= ghc

DEB_CABAL_PACKAGE ?= $(shell cat *.cabal |\
 perl -ne \
 'if (/^name\s*:\s*(.*?)\s*$$/i) {$$_ = $$1; tr/A-Z/a-z/; print; exit 0;}')
CABAL_PACKAGE=$(DEB_CABAL_PACKAGE)
CABAL_VERSION=$(shell cat *.cabal | egrep -i '^\s*version:' | head -n1 | sed -r 's,^\s*version:\s*,,i'| sed -r 's,\s*$$,,i')

DEB_ENABLE_TESTS ?= no
DEB_ENABLE_HOOGLE ?= yes

DEB_DH_GENCONTROL_ARGS_libghc-$(CABAL_PACKAGE)-dev += -- '-DGHC-Package=$${haskell:ghc-package}'

ifneq (,$(filter libghc-$(CABAL_PACKAGE)-prof,$(DEB_PACKAGES)))
ENABLE_PROFILING = --enable-library-profiling
endif

NO_GHCI_FLAG = $(shell test -e /usr/bin/ghci || echo --ghc-option=-DDEBIAN_NO_GHCI; exit 0)

DEB_COMPRESS_EXCLUDE += .haddock .hs .txt

# We do not want to take dependency information
# from libHS*.so files, because
# * dh_haskell_shlibs takes care of that and
# * it would introduced unwanted dependencies on libgmp
# If the latter can be avoided, this could be changed to
# DEB_DH_SHLIBDEPS_ARGS_ALL += -- --ignore-missing-info
# (because we do not (yet) have shlibs files for libHS libraries)
DEB_DH_SHLIBDEPS_ARGS_ALL += -XlibHS
DEB_DH_MAKESHLIBS_ARGS_ALL += -XlibHS

# TODO:
# - some of this would probably be useful for generic Haskell programs,
#   not just libraries
# - provide more hooks
# - get this included in the cdbs package once this gets mature enough (maybe?)

DEB_SETUP_BIN_NAME ?= debian/hlibrary.setup

# most likely you don't need to touch this one
GHC6_VERSION = $(shell ghc --numeric-version)
GHC_VERSION = $(shell ghc --numeric-version)

DEB_HADDOCK_OPTS += --html --hoogle
ifndef DEB_NO_IMPLICIT_HADDOCK_HYPERLINK
DEB_HADDOCK_OPTS += --hyperlink-source
endif

MAKEFILE := debian/hlibrary.Makefile

#ifneq (,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
#    NUMJOBS = $(patsubst parallel=%,%,$(filter parallel=%,$(DEB_BUILD_OPTIONS)))
#    MAKEFLAGS := -j$(NUMJOBS)
#    BUILD_GHC := $(DEB_SETUP_BIN_NAME) makefile -f $(MAKEFILE) && $(MAKE) $(MAKEFLAGS) -f $(MAKEFILE) && $(BUILD_GHC)
#endif

ifneq (,$(findstring noopt,$(DEB_BUILD_OPTIONS)))
   OPTIMIZATION = --disable-optimization
endif

ifeq ($(DEB_ENABLE_TESTS),yes)
ifeq (,$(filter nocheck,$(DEB_BUILD_OPTIONS)))
   TESTS = --enable-tests
endif
endif

DEB_BUILD_DEPENDENCIES = build-arch

# We call the shell for most things, so make our variables available to it
export DEB_SETUP_BIN_NAME
export CABAL_PACKAGE
export CABAL_VERSION
export ENABLE_PROFILING
export NO_GHCI_FLAG
export DEB_SETUP_GHC6_CONFIGURE_ARGS
export DEB_SETUP_GHC_CONFIGURE_ARGS
export OPTIMIZATION
export TESTS
export DEB_DEFAULT_COMPILER
export DEB_PACKAGES
export DEB_HADDOCK_OPTS
export HASKELL_HIDE_PACKAGES
export DEB_GHC_EXTRA_PACKAGES
export DEB_LINTIAN_OVERRIDES_FILE
export DEB_ENABLE_HOOGLE
export MAKEFILE

clean::
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	clean_recipe

$(DEB_SETUP_BIN_NAME):
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	make_setup_recipe

configure-ghc-stamp: $(DEB_SETUP_BIN_NAME)
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	configure_recipe
	touch $@

build-ghc-stamp: configure-ghc-stamp
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	build_recipe
	touch $@

ifeq ($(DEB_ENABLE_TESTS),yes)
ifeq (,$(filter nocheck,$(DEB_BUILD_OPTIONS)))
check-ghc-stamp: build-ghc-stamp
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	check_recipe
	touch $@
else
check-ghc-stamp: build-ghc-stamp
	@echo DEB_BUILD_OPTIONS contains nocheck, not running checks
	touch $@
endif
else
check-ghc-stamp: build-ghc-stamp
	@echo DEB_ENABLE_TESTS not set to yes, not running any tests.
	touch $@
endif

build/libghc-$(CABAL_PACKAGE)-prof build/libghc-$(CABAL_PACKAGE)-dev:: build-ghc-stamp check-ghc-stamp

build/libghcjs-$(CABAL_PACKAGE)-prof build/libghcjs-$(CABAL_PACKAGE)-dev:: build-ghc-stamp check-ghc-stamp

build-haddock-stamp:
	. /usr/share/haskell-devscripts/Dh_Haskell.sh &&\
	haddock_recipe
	touch build-haddock-stamp

build/libghc-$(CABAL_PACKAGE)-doc:: configure-ghc-stamp build-haddock-stamp

build/libghcjs-$(CABAL_PACKAGE)-doc:: configure-ghc-stamp build-haddock-stamp

dist-hugs: $(DEB_SETUP_BIN_NAME)
	$(DEB_SETUP_BIN_NAME) configure --hugs --prefix=/usr -v2 --builddir=dist-hugs $(DEB_SETUP_HUGS_CONFIGURE_ARGS)

build/libhugs-$(CABAL_PACKAGE):: dist-hugs
	$(DEB_SETUP_BIN_NAME) build --builddir=dist-hugs

debian/tmp-inst-ghc: $(DEB_SETUP_BIN_NAME) build-ghc-stamp
	$(DEB_SETUP_BIN_NAME) copy --builddir=dist-ghc --destdir=debian/tmp-inst-ghc

debian/tmp-inst-ghcjs: $(DEB_SETUP_BIN_NAME) build-ghc-stamp
	$(DEB_SETUP_BIN_NAME) copy --builddir=dist-ghcjs --destdir=debian/tmp-inst-ghcjs

debian/extra-depends-ghc: debian/tmp-inst-ghc
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	extra_depends_recipe ghc

debian/extra-depends-ghcjs: debian/tmp-inst-ghcjs
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	extra_depends_recipe ghcjs

DEB_LINTIAN_OVERRIDES_FILE = debian/libghc-$(CABAL_PACKAGE)-dev.lintian-overrides

install/libghc-$(CABAL_PACKAGE)-dev:: debian/tmp-inst-ghc debian/extra-depends-ghc
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	install_dev_recipe "$(notdir $@)"

install/libghcjs-$(CABAL_PACKAGE)-dev:: debian/tmp-inst-ghcjs debian/extra-depends-ghcjs
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	install_dev_recipe "$(notdir $@)"

install/libghc-$(CABAL_PACKAGE)-prof:: debian/tmp-inst-ghc install/libghc-$(CABAL_PACKAGE)-dev debian/extra-depends-ghc
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	install_prof_recipe "$(notdir $@)"

install/libghcjs-$(CABAL_PACKAGE)-prof:: debian/tmp-inst-ghcjs install/libghcjs-$(CABAL_PACKAGE)-dev debian/extra-depends-ghcjs
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	install_prof_recipe "$(notdir $@)"

install/libghc-$(CABAL_PACKAGE)-doc:: debian/tmp-inst-ghc build-haddock-stamp debian/extra-depends-ghc
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	install_doc_recipe "$(notdir $@)"

install/libghcjs-$(CABAL_PACKAGE)-doc:: debian/tmp-inst-ghcjs build-haddock-stamp debian/extra-depends-ghcjs
	. /usr/share/haskell-devscripts/Dh_Haskell.sh && \
	install_doc_recipe "$(notdir $@)"

install/libhugs-$(CABAL_PACKAGE):: $(DEB_SETUP_BIN_NAME) dist-hugs debian/extra-depends-hugs
	$(DEB_SETUP_BIN_NAME) copy --destdir=debian/libhugs-$(CABAL_PACKAGE) --builddir=dist-hugs
	rm -rf debian/libhugs-$(CABAL_PACKAGE)/usr/share/doc/*
	dh_haskell_depends -p$(notdir $@)

# Run dh_haskell_blurbs on all packags, useful e.g. for binary packages
$(patsubst %,install/%,$(DEB_PACKAGES)) :: install/%:
	dh_haskell_blurbs "$(DEB_DEFAULT_COMPILER)" -p$(cdbs_curpkg)


# Support for installing executables
define newline


endef
$(patsubst debian/%.haskell-binaries,build/%,$(wildcard debian/*.haskell-binaries)):: build-ghc-stamp

$(patsubst debian/%.haskell-binaries,install/%,$(wildcard debian/*.haskell-binaries)):: debian/tmp-inst-ghc
	$(foreach binary,$(shell cat debian/$(cdbs_curpkg).haskell-binaries),dh_install -p$(cdbs_curpkg) dist-ghc/build/$(binary)/$(binary) usr/bin $(newline))
