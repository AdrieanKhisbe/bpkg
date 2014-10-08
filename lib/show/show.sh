#!/bin/bash

VERSION="0.0.1"

if ! type -f bpkg-utils &>/dev/null; then
  echo "error: bpkg-utils not found, aborting"
  exit 1
else
  source `which bpkg-utils`
fi

bpkg_initrc

usage () {
  echo "bpkg-show [-Vhds] <user/package_name>"
  echo
  echo "Show bash package details.  You must first run \`bpkg update' to sync the repo locally."
  echo
  echo "Options:"
  echo "  --help|-h     Print this help dialogue"
  echo "  --version|-V  Print version and exit"
  echo "  --details|-d  Print package README.md file, if available"
  echo "  --source|-s   Print all sources listed in package.json scripts, in order. This"
  echo "                option suppresses other output and prints executable bash."
}

show_package () {
  local pkg=$1
  local desc=$2
  local verbose=$3
  local print_source=$4
  local host=$BPKG_REMOTE_HOST
  local remote=$BPKG_REMOTE
  local git_remote=$BPKG_GIT_REMOTE
  local auth=""
  local json=""
  local readme=""
  local uri=""

  if [ "$BPKG_OAUTH_TOKEN" != "" ]; then
    auth="-u $BPKG_OAUTH_TOKEN:x-oauth-basic"
  fi

  if [ "$auth" == "" ]; then
    uri=$BPKG_REMOTE/$pkg/master
  else
    uri=$BPKG_REMOTE/$pkg/raw/master
  fi

  json=$(eval "curl $auth -sL '$uri/package.json?`date +%s`'")
  readme=$(eval "curl $auth -sL '$uri/README.md?`date +%s`'")

  local readme_len=$(echo "$readme" | wc -l | tr -d ' ')

  local version=$(echo "$json" | bpkg-json -b | grep '"version"' | sed 's/.*version"\]\s*//' | tr -d '\t' | tr -d '"')
  local author=$(echo "$json" | bpkg-json -b | grep '"author"' | sed 's/.*author"\]\s*//' | tr -d '\t' | tr -d '"')
  local pkg_desc=$(echo "$json" | bpkg-json -b | grep '"description"' | sed 's/.*description"\]\s*//' | tr -d '\t' | tr -d '"')
  local sources=$(echo "$json" | bpkg-json -b | grep '"scripts"' | cut -f 2 | tr -d '"' )
  local description=$(echo "$json" | bpkg-json -b | grep '"description"')
  local install_sh=$(echo "$json" | bpkg-json -b | grep '"install"' | sed 's/.*install"\]\s*//' | tr -d '\t' | tr -d '"')

  if [ "$pkg_desc" != "" ]; then
    desc="$pkg_desc"
  fi

  if [ "$print_source" == '0' ]; then
    echo "Name: $pkg"
    if [ "$author" != "" ]; then
      echo "Author: $author"
    fi
    echo "Description: $desc"
    echo "Current Version: $version"
    echo "Remote: $git_remote"
    if [ "$install_sh" != "" ]; then
      echo "Install: $install_sh"
    fi
    if [ "$verbose" == "0" ]; then
      if [ "$readme" == "" ]; then
        echo "Readme: Not Available"
      else
        echo "Readme: ${readme_len} lines (-d to print)"
      fi
    else
      echo
      echo "[README.md]"
      echo "$readme"
      echo "[/README.md]"
    fi
  fi
  if [ "$sources" != "" ]; then
    if [ "$print_source" == '0' ]; then
      echo "Sources:"
    fi
    OLDIFS="$IFS"
    IFS=$'\n'
    for src in $(echo "$sources"); do
      if [ "$print_source" == '0' ]; then
        echo " - $src"
      else
        local http_code=$(eval "curl $auth -sL '$uri/$src?`date +%s`' -w '%{http_code}' -o /dev/null")
        if (( http_code < 400 )); then
          local content=$(eval "curl $auth -sL '$uri/$src?`date +%s`'")
          echo "#[$src]"
          echo "$content"
          echo "#[/$src]"
        else
          bpkg_warn "source not found: $src"
        fi
      fi
    done
    IFS="$OLDIFS"
  fi
}


bpkg_show () {
  local verbose=0
  local print_source=0
  local pkg=""
  for opt in "${@}"; do
    case "$opt" in
      -V|--version)
        echo "${VERSION}"
        return 0
        ;;
      -h|--help)
        usage
        return 0
        ;;
      -d|--details)
        verbose=1
        ;;
      -s|--source)
        print_source=1
        ;;
      *)
        if [ "${opt:0:1}" == "-" ]; then
          bpkg_error "unknown option: $opt"
          return 1
        fi
        if [ "$pkg" == "" ]; then
          pkg=$opt
        fi
    esac
  done

  if [ "$pkg" == "" ]; then
    usage
    return 1
  fi

  local i=0
  for remote in "${BPKG_REMOTES[@]}"; do
    local git_remote="${BPKG_GIT_REMOTES[$i]}"
    bpkg_select_remote "$remote" "$git_remote"
    if [ ! -f "$BPKG_REMOTE_INDEX_FILE" ]; then
      bpkg_warn "no index file found for remote: ${remote}"
      bpkg_warn "You should run \`bpkg update' before running this command."
      i=$((i+1))
      continue
    fi

    OLDIFS="$IFS"
    IFS=$'\n'
    for line in $(cat $BPKG_REMOTE_INDEX_FILE); do
      local name=$(echo "$line" | cut -d\| -f1 | tr -d ' ')
      local desc=$(echo "$line" | cut -d\| -f2)
      if [ "$name" == "$pkg" ]; then
        IFS="$OLDIFS"
        show_package "$pkg" "$desc" "$verbose" "$print_source"
        IFS=$'\n'
        return 0
      fi
    done
    IFS="$OLDIFS"
    i=$((i+1))
  done

  bpkg_error "package not found: $pkg"
  return 1
}

if [[ ${BASH_SOURCE[0]} != $0 ]]; then
  export -f bpkg_show
elif bpkg_validate; then
  bpkg_show "${@}"
fi
