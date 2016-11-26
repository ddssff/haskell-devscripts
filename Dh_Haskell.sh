run () {
  echo -n "Running" >&2
  printf " %q" "$@" >&2
  echo              >&2
  "$@"
}

cpu(){
  ghc -ignore-dot-ghci -e 'putStr System.Info.arch'
}

os(){
  ghc -ignore-dot-ghci -e 'putStr System.Info.os'
}

# info ghc "Global Package DB" -> /usr/lib/ghc/package.conf.d
info(){
  local hcexe=$1
  local key=$2
  ${hcexe} --info | ghc -ignore-dot-ghci -e "getContents >>= putStrLn . Data.Maybe.fromJust . lookup \"${key}\" . (read :: String -> [(String, String)])"
}

ghcjs_version(){
  ghcjs --numeric-ghcjs-version
  # Probably equivalant to info ghcjs "Project Version"
}

ghcjs_ghc_version(){
  ghcjs --numeric-ghc-version
}

ghc_version(){
  case $1 in
    ghc) ghc --numeric-version;;
    ghcjs) ghcjs --numeric-ghc-version;;
    *) echo "ghc_version - unexpected compiler \"$1\"" >&2; exit 1;;
  esac
}

package_prefix(){
    echo $1 | sed -n -e 's|^\([^-]*\)-.*-[^-]*$|\1|p'
}

# Extract the compiler name from a package name like libghcjs-text-dev.
# Special case for when the compiler itself is the argument.
package_hc_deb(){
    local deb=$1
    file_package `package_hc_flavor ${deb}`
}

package_hc_flavor(){
    local deb=$1
    case ${deb} in
        ghc|ghc-prof) echo "ghc";;
        *) echo ${deb} | sed -n -e 's|^lib\([^-]*\)-.*-[^-]*$|\1|p';;
    esac
}

file_package(){
    local hcflavor=$1
    dpkg-query -S "`which $1`" | sed 's/: .*//'
}

package_ext(){
    local deb=$1
    case ${deb} in
        # I'm told the ghc build uses these scripts, hence these special cases
        *-prof) echo "prof";;
        ghc*) echo "dev";;
        lib*) echo ${deb} | sed -n -e 's|lib^[^-]*-.*-\([^-]*\)$|\1|p';;
    esac
}

# Collect the compiler list for all the binary debs named in
# DEB_PACKAGES, make sure they all match.
packages_hc_flavor(){
    hcflavors=`{ for i in ${DEB_PACKAGES}; do package_hc_flavor $i; done; } | LC_ALL=C sort -u`
    if [ `echo ${hcflavors} | wc -w` = 0 ]; then hcflavors="ghc"; fi
    if [ `echo ${hcflavors} | wc -w` != 1 ]; then echo "Multiple compilers not supported: ${hcflavors}"; exit 1; fi
    echo ${hcflavors}
}

packages_hc_deb(){
    local DEB_PACKAGES=$1
    file_package "`packages_hc_flavor ${DEB_PACKAGES}`"
}

hc_libdir(){
    local hcflavor=$1
    case ${hcflavor} in
      ghc) echo "usr/lib/haskell-packages/ghc/lib";;
      ghcjs) echo "usr/lib/ghcjs/.cabal/lib";;
      *) echo "Don't know package_libdir for ${hcflavor}" >&2; exit 1;;
    esac
}

package_libdir(){
    local deb=$1
    hc_libdir `package_hc_flavor ${deb}`
}

hc_pkgdir(){
    local hcexe=$1
    info $1 "Global Package DB" | sed 's:^/::'
}

package_pkgdir(){
    local deb=$1
    hc_pkgdir `package_hc_deb ${deb}`
}

hc_prefix(){
    local hcdeb=$1
    case ${hcdeb} in
      ghc) echo "usr";;
      ghcjs) echo "usr/lib/ghcjs";;
      ghc-*) echo "opt/ghc";;
      *) echo "Don't know prefix for compiler ${hcdeb}" >&2; exit 1;;
    esac
}

hc_haddock(){
    local hcflavor=$1
    case ${hcflavor} in
        ghc) which "haddock";;
        ghcjs) which "haddock-ghcjs";;
        *) echo "Don't know haddock dir for ${hcflavor}" >&2; exit 1;;
    esac
}

hc_docdir(){
    local hcdeb=$1
    local pkgid=$2
    echo "usr/lib/${hcdeb}-doc/haddock/${pkgid}/"
}

hc_htmldir(){
    local hcflavor=$1
    local CABAL_PACKAGE=$2
    echo "usr/share/doc/lib${hcflavor}-${CABAL_PACKAGE}-doc/html/"
}

hc_hoogle(){
    local hcdeb=$1
    echo "/usr/lib/${hcdeb}-doc/hoogle/"
}

strip_hash(){
    echo "$1" | sed 's/-................................$//'
}

sort_uniq(){
    {
        for i in "$@" ; do
            echo $i
        done
    } | LC_ALL=C sort -u | tr "\n" " "
}

dependency(){
    local package=$1
    local version=`dpkg-query --showformat='${Version}' -W $package`
    local next_upstream_version=`echo $version | sed  -e 's/-[^-]*$//' -e 's/$/+/'`
    echo "$package (>= $version), $package (<< $next_upstream_version)"
}

ghc_pkg_field(){
    hc=$1
    pkg=$2
    field=$3
    ${hc}-pkg --global field ${pkg} ${field} | head -n1
}

providing_package_for_ghc(){
    local package
    local dep
    local dir
    local dirs
    local lib
    local hc
    local ghcversion=`dpkg-query --showformat '${Version}' --show ghc`
    hc=$1
    if dpkg --compare-versions "${ghcversion}" '>=' 8
    then
        dep=$2
    else
        dep=`strip-hash $2`
    fi
    dirs=`ghc_pkg_field $hc $dep library-dirs | grep -i ^library-dirs | cut -d':' -f 2`
    lib=`ghc_pkg_field $hc $dep hs-libraries | grep -i ^hs-libraries |  sed -e 's|hs-libraries: *\([^ ]*\).*|\1|' `
    for dir in $dirs ; do
        if [ -e "${dir}/lib${lib}.a" ] ; then
            package=`dpkg-query -S ${dir}/lib${lib}.a | cut -d':' -f 1` || exit $?
            continue
        fi
    done
    echo $package
}

providing_package_for_ghc_prof(){
    local package
    local dep
    local dir
    local dirs
    local lib
    local hc
    local ghcversion=`dpkg-query --showformat '${Version}' --show ghc`
    hc=$1
    if dpkg --compare-versions "${ghcversion}" '>=' 8
    then
        dep=$2
    else
        dep=`strip-hash $2`
    fi
    dirs=`ghc_pkg_field $hc $dep library-dirs | grep -i ^library-dirs | cut -d':' -f 2`
    lib=`ghc_pkg_field $hc $dep hs-libraries | grep -i ^hs-libraries | sed -e 's|hs-libraries: *\([^ ]*\).*|\1|' `
    for dir in $dirs ; do
        if [ -e "${dir}/lib${lib}_p.a" ] ; then
            package=`dpkg-query -S ${dir}/lib${lib}_p.a | cut -d':' -f 1` || exit $?
            continue
        fi
    done
    echo $package
}

cabal_package_ids(){
    local config
    local package_ids
    until [ -z "$1" ]
    do
      config=$1
      package_ids="$package_ids `grep-dctrl -n -i -s Id "" $config`"
      shift
    done
    echo $package_ids
}

cabal_depends(){
    local config
    local dep
    local depends
    local final_depends
    until [ -z "$1" ]
    do
      config=$1
      depends="$depends `grep-dctrl -n -i -s Depends "" $config | tr "," " "`"
      shift
    done
    for dep in `sort_uniq $depends` ; do
        # The package is not mentioned in the ignored package list with the same version
        # or mentioned without any version in the ignored package list?
        if  echo " $ignores " | grep -qv " $dep " &&
            echo " $ignores " | grep -qv " `echo $dep | sed s%-[0-9][.0-9a-zA-Z]*$%%` " ;
        then
            final_depends="$final_depends $dep"
        fi
    done
    echo $final_depends
}

hashed_dependency(){
    local hc
    local type
    local pkgid
    local virpkg
    local ghcpkg
    hc=$1
    type=$2
    pkgid=$3
    ghcpkg="`usable_ghc_pkg`"
    virtual_pkg=`package_id_to_virtual_package "${hc}" "$type" $pkgid "${ghcpkg}"`
    # As a transition measure, check if dpkg knows about this virtual package
    if dpkg-query -W $virtual_pkg >/dev/null 2>/dev/null;
    then
         echo $virtual_pkg
    fi
}

depends_for_ghc(){
    local dep
    local packages
    local pkgid
    local hc
    hc=$1
    shift
    for pkgid in `cabal_depends $@` ; do
        dep=`hashed_dependency ${hc} dev $pkgid`
        if [ -z "$dep" ]
        then
          pkg=`providing_package_for_ghc $hc $pkgid`
          if [ -n "$pkg" ]
          then
              dep=`dependency $pkg`
              packages="$packages, $dep"
          else
              echo "WARNING: No Debian package provides haskell package $pkgid." >&2
          fi
        else
            packages="$packages, $dep"
        fi
    done

    echo $packages | sed -e 's/^,[ ]*//'
}

depends_for_ghc_prof(){
    local dep
    local packages
    local pkgid
    local hc
    hc=$1
    shift
    for pkgid in `cabal_depends $@` ; do
        dep=`hashed_dependency ${hc} prof $pkgid`
        if [ -z "$dep" ]
        then
          pkg=`providing_package_for_ghc_prof $hc $pkgid`
          if [ -n "$pkg" ]
          then
              dep=`dependency $pkg`
              packages="$packages, $dep"
          else
              echo "WARNING: No Debian package provides haskell package $pkgid." >&2
          fi
        else
            packages="$packages, $dep"
        fi
    done

    echo $packages | sed -e 's/^,[ ]*//'
}

usable_ghc_pkg() {
    local ghcpkg
    local version
    if [ -x inplace/bin/ghc-pkg ]
    then
        # We are building ghc and need to use the new ghc-pkg
        ghcpkg="inplace/bin/ghc-pkg"
        version="`dpkg-parsechangelog -S Version`"
    else
        ghcpkg="ghc-pkg"
        version="`dpkg-query --showformat '${Version}' --show ghc`"
    fi
    # ghc-pkg prior to version 8 is unusable for our purposes.
    if dpkg --compare-versions "$version" '>=' 8
    then
        echo "${ghcpkg}"
    fi
}

tmp_package_db() {
    local ghcpkg
    ghcpkg="`usable_ghc_pkg`"
    if [ -n "${ghcpkg}" ]
    then
        if [ ! -f debian/tmp-db/package.cache ]
        then
            mkdir debian/tmp-db
            cp $@ debian/tmp-db/
            $ghcpkg --package-db debian/tmp-db/ recache
        fi
        echo "${ghcpkg} --package-db debian/tmp-db"
    fi
}

provides_for_ghc(){
    local hc
    local dep
    local packages
    hc=$1
    shift
    ghcpkg="`tmp_package_db $@`"
    for package_id in `cabal_package_ids $@` ; do
        packages="$packages, `package_id_to_virtual_package "${hc}" dev $package_id "${ghcpkg}"`"
    done
    echo $packages | sed -e 's/^,[ ]*//'
}

provides_for_ghc_prof(){
    local hc
    local dep
    local packages
    hc=$1
    shift
    ghcpkg="`tmp_package_db $@`"
    for package_id in `cabal_package_ids $@` ; do
        packages="$packages, `package_id_to_virtual_package "${hc}" prof $package_id "${ghcpkg}"`"
    done
    echo $packages | sed -e 's/^,[ ]*//'
}

package_id_to_virtual_package(){
        local hc
        local type
        local pkgid
        local ghcpkg
        hc="$1"
        type="$2"
        pkgid="$3"
        ghcpkg="$4"
        if [ -n "$ghcpkg" ]
        then
            name=`${ghcpkg} --simple-output field "${pkgid}" name`
            version=`${ghcpkg} --simple-output field "${pkgid}" version`
            abi=`${ghcpkg} --simple-output field "${pkgid}" abi | cut -c1-5`
            echo "lib${hc}-${name}-${type}-${version}-${abi}" | tr A-Z a-z
        else
            # We don't have a usable ghc-pkg, so we fall back to parsing the package id.
            echo ${pkgid} | tr A-Z a-z | \
                grep '[a-z0-9]\+-[0-9\.]\+-................................' | \
                perl -pe 's/([a-z0-9-]+)-([0-9\.]+)-(.....).........................../lib'${hc}'-\1-'$type'-\2-\3/'
        fi
}

depends_for_hugs(){
    local version
    local upstream_version
    version=`dpkg-query --showformat='${Version}' -W hugs`
    upstream_version=`echo $version | sed -e 's/-[^-]*$//'`
    echo "hugs (>= $upstream_version)"
}

find_config_for_ghc(){
    local f
    local pkg
    pkg=$1
    pkgdir=`package_pkgdir ${pkg}`
    case "$pkg" in
        ghc-prof)
            pkg=ghc
            ;;
        *-prof)
            pkg=`echo $pkg | sed -e 's/-prof$/-dev/'`
            ;;
        *)
            ;;
    esac
    for f in debian/$pkg/${pkgdir}/*.conf ; do
        if [ -f "$f" ] ; then
            echo $f
            echo " "
        fi
    done
}

clean_recipe(){
    # local PS5=$PS4; PS4=" + clean_recipe> "; set -x
    [ ! -x "${DEB_SETUP_BIN_NAME}" ] || run ${DEB_SETUP_BIN_NAME} clean
    run rm -rf dist dist-ghc* dist-ghcjs* dist-hugs* ${DEB_SETUP_BIN_NAME} Setup.hi Setup.ho Setup.o .*config*
    run rm -f configure-ghc-stamp configure-ghcjs-stamp build-ghc-stamp build-ghcjs-stamp build-hugs-stamp build-haddock-stamp
    run rm -rf debian/tmp-inst-ghc debian/tmp-inst-ghcjs
    run rm -f debian/extra-depends-ghc debian/extra-depends-ghcjs
    if [ -f ${DEB_LINTIAN_OVERRIDES_FILE} ] ; then
      run sed -i '/binary-or-shlib-defines-rpath/ d' ${DEB_LINTIAN_OVERRIDES_FILE}
      run find ${DEB_LINTIAN_OVERRIDES_FILE} -empty -delete;
    fi

    run rm -f ${MAKEFILE}
    run rm -rf debian/dh_haskell_shlibdeps
    run rm -rf debian/tmp-db
    # PS4=$PS5
}

make_setup_recipe(){
    # local PS5=$PS4; PS4=" + make_setup_recipe> "; set -x
    for setup in Setup.lhs Setup.hs
    do
      if test -e $setup
      then
        run ghc --make $setup -o ${DEB_SETUP_BIN_NAME}
    exit 0
      fi
    done
    # PS4=$PS5
}

configure_recipe(){
    # local PS5=$PS4; PS4=" + configure_recipe> "; set -x
    hcflavor=`packages_hc_flavor ${DEB_PACKAGES}`
    hcdeb=`packages_hc_deb ${DEB_PACKAGES}`

    ENABLE_PROFILING=`{ for i in ${DEB_PACKAGES}; do package_ext $i | grep prof; done; } | LC_ALL=C sort -u | sed 's/prof/--enable-library-profiling/'`
    local GHC_OPTIONS
    for i in `dpkg-buildflags --get LDFLAGS`
    do
        GHC_OPTIONS="$GHC_OPTIONS --ghc-option=-optl$i"
    done

    # DEB_SETUP_GHC_CONFIGURE_ARGS can contain multiple arguments with their own quoting,
    # so run this through eval
    eval run ${DEB_SETUP_BIN_NAME} \
        configure "--${hcflavor}" \
        -v2 \
        --package-db=/`hc_pkgdir ${hcflavor}` \
        --prefix=/`hc_prefix ${hcdeb}` \
        --libdir=/`hc_libdir ${hcflavor}` \
        --libexecdir=/usr/lib \
        --builddir=dist-${hcdeb} \
        ${GHC_OPTIONS} \
        --haddockdir=/`hc_docdir ${hcflavor} ${CABAL_PACKAGE}-${CABAL_VERSION}` \
        --datasubdir=${CABAL_PACKAGE}\
        --htmldir=/`hc_htmldir ${hcflavor} ${CABAL_PACKAGE}` \
        ${ENABLE_PROFILING} \
        ${NO_GHCI_FLAG} \
        ${DEB_SETUP_GHC6_CONFIGURE_ARGS} \
        ${DEB_SETUP_GHC_CONFIGURE_ARGS} \
        ${OPTIMIZATION} \
        ${TESTS}
    # PS4=$PS5
}

build_recipe(){
    # local PS5=$PS4; PS4=" + build_recipe> "; set -x
    hcdeb=`packages_hc_deb ${DEB_PACKAGES}`
    run ${DEB_SETUP_BIN_NAME} build --builddir=dist-${hcdeb}
    # PS4=$PS5
}

check_recipe(){
    # local PS5=$PS4; PS4=" + check_recipe> "; set -x
    hcdeb=`packages_hc_deb ${DEB_PACKAGES}`
    version=`ghc_version ${hc}`
    if dpkg --compare-versions "$version" '>=' 8; then arg=direct; else arg="always"; fi
    run ${DEB_SETUP_BIN_NAME} test --builddir=dist-${hcdeb} --show-details=$arg
    # PS4=$PS5
}

haddock_recipe(){
    # local PS5=$PS4; PS4=" + haddock_recipe> "; set -x
    hcflavor=`packages_hc_flavor ${DEB_PACKAGES}`
    hcdeb=`packages_hc_deb ${DEB_PACKAGES}`
    haddock=`hc_haddock ${hcflavor}`
    if [ -x ${haddock} ] && \
          ! run ${DEB_SETUP_BIN_NAME} haddock --builddir=dist-${hcdeb} --with-haddock=${haddock} --with-ghc=${hcflavor} --verbose=2 ${DEB_HADDOCK_OPTS} ; then
       echo "Haddock failed (no modules?), refusing to create empty documentation package."
       exit 1
    fi
    # PS4=$PS5
}

extra_depends_recipe(){
    # local PS5=$PS4; PS4=" + extra_depends_recipe> "; set -x
    hcdeb=$1
    pkg_config=`${DEB_SETUP_BIN_NAME} register --builddir=dist-${hcdeb} --gen-pkg-config | tr -d ' \n' | sed -r 's,^.*:,,'`
    run dh_haskell_extra_depends ${hcdeb} $pkg_config
    rm $pkg_config
    # PS4=$PS5
}

install_dev_recipe(){
    # local PS5=$PS4; PS4=" + install_dev_recipe> "; set -x
    PKG=$1

    hcdeb=`package_hc_deb ${PKG}`
    libdir=`package_libdir ${PKG}`
    pkgdir=`package_pkgdir ${PKG}`

    ( run cd debian/tmp-inst-${hcdeb} ; run mkdir -p ${libdir} ; run find ${libdir}/ \
        \( ! -name "*_p.a" ! -name "*.p_hi" ! -type d \) \
        -exec install -Dm 644 '{}' ../${PKG}/'{}' ';' )
    pkg_config=`${DEB_SETUP_BIN_NAME} register --builddir=dist-${hcdeb} --gen-pkg-config | tr -d ' \n' | sed -r 's,^.*:,,'`
    if [ "${HASKELL_HIDE_PACKAGES}" ]; then sed -i 's/^exposed: True$/exposed: False/' $pkg_config; fi
    run install -Dm 644 $pkg_config debian/${PKG}/${pkgdir}/$pkg_config
    run rm -f $pkg_config
    if [ "z${DEB_GHC_EXTRA_PACKAGES}" != "z" ] ; then
       EP_DIR=debian/${PKG}/usr/lib/haskell-packages/extra-packages
       run mkdir -p $EP_DIR
       echo "${DEB_GHC_EXTRA_PACKAGES}" > ${EP_DIR}/${CABAL_PACKAGE}-${CABAL_VERSION}
    fi

    grep -s binary-or-shlib-defines-rpath ${DEB_LINTIAN_OVERRIDES_FILE} \
       || echo binary-or-shlib-defines-rpath >> ${DEB_LINTIAN_OVERRIDES_FILE}
    run dh_haskell_provides -p${PKG}
    run dh_haskell_depends -p${PKG}
    run dh_haskell_shlibdeps -p${PKG}
    # PS4=$PS5
}

install_prof_recipe(){
    # local PS5=$PS4; PS4=" + install_prof_recipe> "; set -x
    PKG=$1
    libdir=`package_libdir ${PKG}`
    ( run cd debian/tmp-inst-`package_hc_deb ${PKG}`
      run mkdir -p ${libdir}
      run find ${libdir}/ \
        ! \( ! -name "*_p.a" ! -name "*.p_hi" \) \
        -exec install -Dm 644 '{}' ../${PKG}/'{}' ';' )
    run dh_haskell_provides -p${PKG}
    run dh_haskell_depends -p${PKG}
    # PS4=$PS5
}

install_doc_recipe(){
    # local PS5=$PS4; PS4=" + install_doc_recipe> "; set -x
    PKG=$1
    hcdeb=`package_hc_deb ${PKG}`
    pkgid=${CABAL_PACKAGE}-${CABAL_VERSION}
    docdir=`hc_docdir ${hcdeb} ${pkgid}`
    htmldir=`hc_htmldir ${hcflavor} ${CABAL_PACKAGE}`
    hoogle=`hc_hoogle ${hcdeb}`
    run mkdir -p debian/${PKG}/${htmldir}
    ( run cd debian/tmp-inst-${hcdeb}/ ;
      run find ./${htmldir} \
        ! -name "*.haddock" ! -type d -exec install -Dm 644 '{}' \
        ../${PKG}/'{}' ';' )
    run mkdir -p debian/${PKG}/${docdir}
    [ 0 = `ls debian/tmp-inst-${hcdeb}/${docdir}/ 2>/dev/null | wc -l` ] ||
        run cp -r debian/tmp-inst-${hcdeb}/${docdir}/*.haddock debian/${PKG}/${docdir}
    if [ "${DEB_ENABLE_HOOGLE}" = "yes" ]
    then
        # We cannot just invoke dh_link here because that acts on
        # either libghc-*-dev or all the binary packages, neither of
        # which is desirable (see dh_link (1)).  So we just create a
        # (policy-compliant) symlink ourselves
        source=`find debian/${PKG}/${htmldir} -name "*.txt"`
        dest=debian/${PKG}${hoogle}${PKG}.txt
        run mkdir -p `dirname $dest`
        run ln -rs -T $source $dest
    fi
    run dh_haskell_depends -p${PKG}
    # PS4=$PS5
}

if ! [ `which grep-dctrl` > /dev/null ] ; then
    echo "grep-dctrl is missing" >&2
    exit 1
fi

args=
ignores=
files=
until [ -z "$1" ]
do
  case "$1" in
      -X*)
          pkg=${1##-X}
          ignores="$ignores $pkg"
          ;;

      --exclude=*)
          pkg=${1##--exclude=}
          ignores="$ignores $pkg"
          ;;

      -*)
          args="$args $1"
          ;;
      *)
          if [ -f $1 ] ; then
              files="$files $1"
          else
              echo "Installed package description file $1 can not be found" >&2
              exit 1
          fi
          ;;
  esac
  shift
done
