sort_uniq(){
    {
	for i in "$@" ; do
	    echo $i
	done
    } | sort -u | tr "\n" " "
}

dependency(){
    local package
    local version
    local next_upstream_version
    package=$1
    version=`dpkg-query --showformat='${Version}' -W $package`
    next_upstream_version=`echo $version | sed  -e 's/-[^-]*$//' -e 's/$/+/'`
    echo "$package (>= $version), $package (<< $next_upstream_version)"
}

dependencies(){
    local package
    local packages
    local deps
    packages=$@
    for package in `sort_uniq $packages` ; do
	deps="$deps, `dependency $package`"
    done

    echo $deps | sed -e 's/^,[ ]*//'
}

providing_package_for_ghc6(){
    local package
    local dep
    local dir
    local dirs
    local lib
    dep=$1
    dirs=`ghc-pkg6 field $dep library-dirs | cut -d':' -f 2`
    lib=`ghc-pkg6 field $dep hs-libraries | sed -e 's|hs-libraries: *\([^ ]*\).*|\1|' `
    for dir in $dirs ; do
	if [ -e "${dir}/lib${lib}.a" ] ; then
	    package=`dpkg-query -S ${dir}/lib${lib}.a | cut -d':' -f 1` || exit $?
	    continue
	fi
    done
    echo $package
}

providing_package_for_ghc6_prof(){
    local package
    local dep
    local dir
    local dirs
    local lib
    dep=$1
    dirs=`ghc-pkg6 field $dep library-dirs | cut -d':' -f 2`
    lib=`ghc-pkg6 field $dep hs-libraries | sed -e 's|hs-libraries: *\([^ ]*\).*|\1|' `
    for dir in $dirs ; do
	if [ -e "${dir}/lib${lib}_p.a" ] ; then
	    package=`dpkg-query -S ${dir}/lib${lib}_p.a | cut -d':' -f 1` || exit $?
	    continue
	fi
    done
    echo $package
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

depends_for_ghc6(){
    local dep
    local packages
    for dep in `cabal_depends $@` ; do
	packages="$packages `providing_package_for_ghc6 $dep`"
    done

    dependencies $packages
}

depends_for_ghc6_prof(){
    local dep
    local packages
    for dep in `cabal_depends $@` ; do
	packages="$packages `providing_package_for_ghc6_prof $dep`"
    done

    dependencies $packages
}

depends_for_hugs(){
    local version
    local upstream_version
    version=`dpkg-query --showformat='${Version}' -W hugs`
    upstream_version=`echo $version | sed -e 's/-[^-]*$//'`
    echo "hugs (>= $upstream_version)"
}

find_config_for_ghc6(){
    local f
    local pkg
    pkg=$1
    case "$pkg" in
	libghc6-*-prof)
	    pkg=`echo $pkg | sed -e 's/-prof$/-dev/'`
	    ;;
	*)
	    ;;
    esac
    for f in debian/$pkg/var/lib/ghc-*/packages.conf.d/* ; do
	if [ -f "$f" ] ; then
	    echo $f
	    break
	fi
    done
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

