#!/usr/bin/perl
# debhelper sequence file for haskell-devscripts

use warnings;
use strict;
use Debian::Debhelper::Dh_Lib;

insert_before("dh_auto_build", "dh_haskell_prep");
insert_before("dh_auto_build", "dh_haskell_configure");
insert_before("dh_auto_build", "dh_haskell_build");
insert_before("dh_compress", "dh_compress -X.haddock");
remove_command("dh_compress");
insert_before("dh_install", "dh_haskell_install");
insert_before("dh_gencontrol", "dh_haskell_depends");
insert_before("dh_gencontrol", "dh_haskell_shlibdeps");
insert_before("dh_clean", "dh_haskell_clean");

1
