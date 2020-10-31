#!/bin/bash

# exit on any error:
set -eE

# top level function:
mframe_modules() {
  local command=$1
  local RES=

  local mod_repo=
  local mod_repo_confirmed=false
  local mod_name=
  local mod_dirname=
  local mod_dir=
  local mod_upstream_commit=
  local mod_local_commit=
  local mod_version=
  local mod_versions=
  local mod_versions_prefixed=
  local mod_latest_version=
  local mod_latest_version_prefixed=
  local mod_ahead=0
  local mod_behind=0
  local mod_v=
  local mod_local=true
  
  local git_main_branch=
  local git_temp_branch=
  local git_stashed="n"

  # match repository URLs:
  local repourl_regex="^(https?|git)(:\/\/|@)([^\/:]+)[\/:]([^\/]+)\/([^\/]+)(\.git)?$"

  # perl equivalent of envsubst:
  local replace_cmd='perl -pe '"'"'s/\$\{([^\}]+)\}/$ENV{$1}/g'"'"

  if [ ! -d "$ROOT_DIR/.git" ]; then
    mframe_utils_error "Not inside a GIT repository."
  fi

  # execute desired command:
  "mframe_modules_$command"
}

#
# ------------------------------------------------------------------------------
#

# `make module name=...` command:
mframe_modules_create() {
  mframe_modules_set_current "$MODULE_NAME"

  if [ -d "$mod_dir" ]; then
    mframe_utils_error "Module \"$mod_name\" already exists."
  fi

  # ask for module repository, unless already confirmed:
  if ! $mod_repo_confirmed; then
    mframe_utils_input "Module GIT repository:" "$mod_repo" true; mod_repo="$RES"
  fi

  # ask for module template:
  mframe_utils_input "Module template:" "$MODULES_TPL"; local tpl="$RES"

  # do the work on a temp branch for easy error recovery:
  mframe_utils_git_create_temp_branch

  # in case of any errors remove temp branch and restore initial state:
  trap 'mframe_utils_git_remove_temp_branch' ERR INT

  RUN mkdir -p $MODULES_DIR

  if [ ! -z "$tpl" ]; then
    if [[ "$tpl" =~ $repourl_regex ]]; then
      RUN git clone -q $tpl $mod_dir
      RUN rm -rf $mod_dir/.git
    elif [ -d "$MODULES_DIR/.$tpl" ]; then
      RUN cp -r $MODULES_DIR/.$tpl $mod_dir
    elif [ -d "$CLI_DIR/templates/$tpl" ]; then
      RUN cp -r $CLI_DIR/templates/$tpl $mod_dir
    fi
  fi

  # if no module template provided, create a "blank" module:
  if [ ! -d "$mod_dir" ]; then
    RUN cp -r $CLI_DIR/templates/blank $mod_dir
  fi

  # substitute placeholders:
  RUN find $mod_dir -type f -exec sh -c \
    "REPO=$mod_repo NAME=$mod_name DIR=$mod_dirname $replace_cmd < {} > {}.tmp && mv {}.tmp {}" \;

  # commit the new module and make it a subrepo:
  RUN git add $mod_dir
  RUN git commit -q -m "chore(mframe): created module \"$mod_name\"" $mod_dir
  RUN git subrepo init $mod_dir -r $mod_repo -b v1 -q

  # merge changes made on the temp branch and discard it:
  mframe_utils_git_merge_temp_branch

  echo "Module \"$mod_name\" created in \"$mod_dir\"."

  RUN make _module-created repo=$mod_repo name=$mod_name dir=$mod_dirname
}

# `make module-install name=... [v=latest]` command:
mframe_modules_install() {
  mframe_modules_set_current "$MODULE_NAME"

  # do the work on a temp branch for easy error recovery:
  mframe_utils_git_create_temp_branch

  # in case of any errors remove temp branch and restore initial state:
  trap 'mframe_utils_git_remove_temp_branch' ERR INT

  local v="$MODULE_V"
  if [ -z "$v" -o "$v" == "latest" ]; then
    mframe_modules_get_versions
    v="$mod_latest_version"
  fi

  RUN git subrepo clone $mod_repo -b v$v $([ -d "$mod_dir" ] && echo "-f") $mod_dir -q
  RUN make _module-install-hook _module-cfgadd repo=$mod_repo name=$mod_name dir=$mod_dirname

  if ! git diff --quiet; then
    RUN git add .
    RUN git commit -q --amend --no-edit
  fi

  # merge changes made on the temp branch and discard it:
  mframe_utils_git_merge_temp_branch

  echo "Module \"$mod_name\" (v$v) installed in \"$mod_dir\"."

  RUN make _module-installed repo=$mod_repo name=$mod_name dir=$mod_dirname
}

# `make module-update name=...` command:
mframe_modules_update() {
  mframe_modules_set_current "$MODULE_NAME"

  if [ ! -d "$mod_dir" ]; then
    mframe_utils_error "No module found at \"$mod_dir\"."
  fi

  if $mod_local; then
    echo "Module \"$mod_name\" is not published, skipping update."
    return 0
  fi

  # do the work on a temp branch for easy error recovery:
  mframe_utils_git_create_temp_branch

  # in case of any errors remove temp branch and restore initial state:
  trap 'mframe_utils_git_remove_temp_branch' ERR INT

  RUN git subrepo clean $mod_dir -q
  RUN git subrepo pull $mod_dir -q -f

  # merge changes made on the temp branch and discard it:
  mframe_utils_git_merge_temp_branch

  echo "Module \"$mod_name\" updated."

  RUN make _module-updated repo=$mod_repo name=$mod_name dir=$mod_dirname
}

# `make module-update-all` command:
mframe_modules_update_all() {
  for subrepo in $(git subrepo status --quiet); do
    MODULE_NAME=$(basename $subrepo) mframe_modules_update
  done

  RUN make _module-updated-all
}

# `make module-publish name=...` command:
mframe_modules_publish() {
  mframe_modules_set_current "$MODULE_NAME"

  if [ ! -d "$mod_dir" ]; then
    mframe_utils_error "No module found at \"$mod_dir\"."
  fi

  if $mod_local; then
    echo
    echo "Module \"$mod_name\" is now published for the first time, please make"
    echo "sure its upstream repository is created before continuing."
    echo
    echo "The upstream repository for this module should be:"
    echo $mod_repo
    echo
    
    if ! mframe_utils_confirm "Continue?" "y"; then
      return 0
    fi

    echo
  fi

  local publish_success=false
  local publish_branch=

  if [ ! -z "$MODULE_V" ]; then
    # user-managed versioning mode, publish to specified version:
    mframe_modules_publish_manual $MODULE_V
  else
    mframe_modules_upstream_diff

    if [ $mod_behind -gt 0 ]; then
      mframe_utils_error "Module \"$mod_name\" is behind upstream, update before publishing."
    else
      if [ $mod_ahead -gt 0 ] || $mod_local; then
        if which -s standard-version; then
          mframe_modules_publish_auto
        else
          mframe_modules_publish_manual
        fi
      else
        echo "Module \"$mod_name\" has no commits ahead."
      fi
    fi
  fi

  if $publish_success; then
    echo "Module \"$mod_name\" ($publish_branch) published."

    RUN make _module-published repo=$mod_repo name=$mod_name dir=$mod_dirname
  fi
}

# `make module-publish-all` command:
mframe_modules_publish_all() {
  for subrepo in $(git subrepo status --quiet); do
    MODULE_NAME=$(basename $subrepo) mframe_modules_publish
  done

  RUN make _module-published-all
}

# `make module-remove name=...` command:
mframe_modules_remove() {
  mframe_modules_set_current "$MODULE_NAME"

  if [ ! -d "$mod_dir" ]; then
    mframe_utils_error "No module found at \"$mod_dir\"."
  fi

  if ! git diff --quiet $mod_dir || ! git diff --cached --quiet $mod_dir; then
    mframe_utils_error "Module has uncommitted changes, so it can't be deleted."
  fi

  # do the work on a temp branch for easy error recovery:
  mframe_utils_git_create_temp_branch

  # in case of any errors remove temp branch and restore initial state:
  trap 'mframe_utils_git_remove_temp_branch' ERR INT

  RUN make _module-remove-hook repo=$mod_repo name=$mod_name dir=$mod_dirname

  if [ -f "$mod_dir/.gitrepo" ]; then
    RUN git subrepo clean $mod_dir -q
  fi

  RUN rm -rf $mod_dir
  RUN git add $mod_dir
  RUN git commit -q -m "chore(mframe): removed module \"$mod_name\"" $mod_dir/*

  RUN make _module-cfgrem repo=$mod_repo name=$mod_name dir=$mod_dirname

  if ! git diff --quiet; then
    RUN git add .
    RUN git commit -q --amend --no-edit
  fi

  # merge changes made on the temp branch and discard it:
  mframe_utils_git_merge_temp_branch

  echo "Module \"$mod_name\" removed."

  RUN make _module-removed repo=$mod_repo name=$mod_name dir=$mod_dirname
}

# `make module-status [name=...]` command:
mframe_modules_status() {
  # a list of modules that have uncommitted changes:
  local wip_modules="$(mframe_modules_list_uncommitted)"

  mframe_utils_git_stash_push

  if [ ! -z "$MODULE_NAME" ]; then
    mframe_modules_set_current "$MODULE_NAME"

    if [ ! -d "$mod_dir" ]; then
      mframe_utils_error "No module found at \"$mod_dir\"."
    fi
  fi

  local uncommitted=
  local first=true
  for subrepo in $(git subrepo status $mod_dir --quiet); do
    if $first; then
      echo "Ahead / Behind     Module"
      first=false
    fi

    mframe_modules_set_current $(basename $subrepo)
    mframe_modules_upstream_diff

    local upgrade=

    if ! $mod_local; then
      mframe_modules_get_versions
      if [ "$mod_version" != "$mod_latest_version" ]; then
        upgrade=" [v$mod_latest_version available]"
      fi
    fi

    if echo "$wip_modules" | grep -Eq "([^[:alnum:]_.-]|^)$subrepo([^[:alnum:]_.-]|$)"; then
      uncommitted=" ** has uncommitted changes **"
    else
      uncommitted=
    fi

    printf %5s $mod_ahead
    printf " / "
    printf %-11s $mod_behind
    echo "$mod_dirname ($mod_v)$upgrade$uncommitted"
  done

  mframe_utils_git_stash_pop
}

# `make module-info [name=...]` command:
mframe_modules_info() {
  # a list of modules that have uncommitted changes:
  local wip_modules="$(mframe_modules_list_uncommitted)"

  mframe_utils_git_stash_push
  trap 'mframe_utils_git_stash_pop' ERR INT

  if [ ! -z "$MODULE_NAME" ]; then
    mframe_modules_set_current "$MODULE_NAME"

    if [ ! -d "$mod_dir" ]; then
      mframe_utils_error "No module found at \"$mod_dir\"."
    fi
  fi

  local pad="-17"

  local uncommitted=
  for subrepo in $(git subrepo status $mod_dir --quiet); do
    mframe_modules_set_current $(basename $subrepo)
    mframe_modules_upstream_diff

    if ! $mod_local; then
      mframe_modules_get_versions
    fi

    if echo "$wip_modules" | grep -Eq "([^[:alnum:]_.-]|^)$subrepo([^[:alnum:]_.-]|$)"; then
      uncommitted=" ** has uncommitted changes **"
    else
      uncommitted=
    fi

    echo "Module \"$mod_name\":"
    printf %${pad}s "  Repo URL:"
    echo $mod_repo
    printf %${pad}s "  Versions:"
    if $mod_local; then
      echo "[$mod_version]"
    else
      echo $mod_versions | sed -E "s/(^|[[:space:]])$mod_version([[:space:]]|$)/\1[$mod_version]\2/g"
    fi
    printf %${pad}s "  Diff Status:"
    if $mod_local; then
      echo "unpublished $uncommitted"
    else
      echo "$mod_ahead ahead, $mod_behind behind $uncommitted"
    fi

    if [ $mod_ahead -gt 0 ]; then
      echo; echo "  Commits ahead:"
      git log --pretty=format:%s FETCH_HEAD..$mod_local_commit | awk '{print "    "$0}'
    fi

    if [ $mod_behind -gt 0 ]; then
      echo; echo "  Commits behind:"
      git log --pretty=format:%s $mod_local_commit..FETCH_HEAD | awk '{print "    "$0}'
    fi

    echo; echo
  done

  mframe_utils_git_stash_pop
}

# `make module-gitrepo-reset [name=...]` command:
mframe_modules_gitrepo_reset() {
  local head=$(git rev-parse HEAD)

  # do the work on a temp branch for easy error recovery:
  mframe_utils_git_create_temp_branch

  # in case of any errors remove temp branch and restore initial state:
  trap 'mframe_utils_git_remove_temp_branch' ERR INT

  if [ ! -z "$MODULE_NAME" ]; then
    mframe_modules_set_current "$MODULE_NAME"
  fi

  for subrepo in $(git subrepo status $mod_dir --quiet); do
    mframe_modules_set_current $(basename $subrepo)

    say sed -e "s/parent =.*$/parent = $head/" $mod_dir/.gitrepo "> $mod_dir/.gitrepo.tmp"
    sed -e "s/parent =.*$/parent = $head/" $mod_dir/.gitrepo > $mod_dir/.gitrepo.tmp
    RUN mv $mod_dir/.gitrepo.tmp $mod_dir/.gitrepo
  done

  if ! git diff --quiet; then
    RUN git add .
    RUN git commit -q -m "chore(mframe): .gitrepo reset"
  fi

  # merge changes made on the temp branch and discard it:
  mframe_utils_git_merge_temp_branch
}

#
# ------------------------------------------------------------------------------
#

mframe_modules_state() {
  echo mod_repo = $mod_repo
  echo mod_repo_confirmed = $mod_repo_confirmed
  echo mod_name = $mod_name
  echo mod_dirname = $mod_dirname
  echo mod_dir = $mod_dir
  echo mod_upstream_commit = $mod_upstream_commit
  echo mod_local_commit = $mod_local_commit
  echo mod_version = $mod_version
  echo mod_versions = $mod_versions
  echo mod_versions_prefixed = $mod_versions_prefixed
  echo mod_latest_version = $mod_latest_version
  echo mod_latest_version_prefixed = $mod_latest_version_prefixed
  echo mod_ahead = $mod_ahead
  echo mod_behind = $mod_behind
  echo mod_v = $mod_v
  echo mod_local = $mod_local
}

# set current  module, given its "identifier" (repo, name or local dir):
# $1 - module identifier
mframe_modules_set_current() {
  mod_repo=
  mod_repo_confirmed=false
  mod_name=
  mod_dirname=
  mod_dir=
  mod_upstream_commit=
  mod_local_commit=
  mod_version=
  mod_versions=
  mod_versions_prefixed=
  mod_latest_version=
  mod_latest_version_prefixed=
  mod_ahead=0
  mod_behind=0
  mod_v=
  mod_local=true

  local identifier="$1"

  if [ -z "$identifier" ]; then
    mframe_utils_input "Module ID (repo, name or dir):" "" true; identifier="$RES"
  fi

  if [[ "$identifier" =~ $repourl_regex ]]; then
    # user input is a repository URL from which we can infer the module's name
    # and its local directory
    mod_repo="$identifier"
    mod_repo_confirmed=true
  else
    # user input is either a local module directory or a module name
    mframe_modules_strip_prefix $identifier; mod_dirname="$RES"

    if [ -d "$MODULES_DIR/$mod_dirname" ]; then
      # in case a .gitrepo file is available, extract the repository URL:
      if [ -f "$MODULES_DIR/$mod_dirname/.gitrepo" ]; then
        mod_repo=$(cat $MODULES_DIR/$mod_dirname/.gitrepo | grep remote | awk '{print $3}')
        mod_repo_confirmed=true
      fi
    else
      mod_name="$identifier"

      # in case the name does not start with the configured prefix we ask for
      # confirmation:
      if [ "$mod_dirname" == "$identifier" -a ! -z "$MODULES_PFX" ]; then
        if mframe_utils_confirm "Did you mean '$MODULES_PFX$identifier'?" "y"; then
          mod_name="$MODULES_PFX$identifier"
        fi
      fi

      if [ ! -z "$MODULES_GIT" ]; then
        mod_repo="$MODULES_GIT/$mod_name"
      fi
    fi
  fi

  if $mod_repo_confirmed; then
    if [ -z "$mod_name" ]; then
      mod_name=$(basename "$mod_repo" .git)
    fi

    if [ -z "$mod_dirname" ]; then
      mframe_modules_strip_prefix $mod_name; mod_dirname="$RES"
    fi
  fi

  if [ ! -z "$mod_dirname" ]; then
    mod_dir="$MODULES_DIR/$mod_dirname"
  fi

  if [ -f "$mod_dir/.gitrepo" ]; then
    mod_upstream_commit=$(cat $mod_dir/.gitrepo | grep commit | awk '{print $3}')
    mod_version=$(cat $mod_dir/.gitrepo | grep branch | awk '{print $3}' | sed -e 's/^v//')

    if [ ! -z "$mod_upstream_commit" ]; then
      mod_local=false
      mod_v="v$mod_version"
    else
      mod_v="unpublished"
    fi
  fi
}

# strip $MODULES_PFX (if defined) from the given string:
# $1 - input string
mframe_modules_strip_prefix() {
  if [ ! -z "$MODULES_PFX" ]; then
    RES=$(sed "s/^$MODULES_PFX//" <<< $1)
  else
    RES="$1"
  fi
}

# get all versions for the current module:
# $1 - version prefix (optional)
mframe_modules_get_versions() {
  if [ ! -z "$mod_versions" ]; then
    return 0
  fi

  mframe_modules_update_repo

  mod_versions=$(git branch -r | grep -e '^  origin/v' | sed -e 's;  origin/v;;' | sort -rV)
  mod_latest_version=$(echo "$mod_versions" | head -1)

  if [ ! -z "$1" ]; then
    mod_versions_prefixed=$(echo "$mod_versions" | grep "$1" | sort -rV)
    mod_latest_version_prefixed=$(echo "$mod_versions_prefixed" | head -1)
  fi

  RUN cd $ROOT_DIR
}

# clone/update the repo for the current module:
mframe_modules_update_repo() {
  RUN mkdir -p $MODULES_TMP
  RUN cd $MODULES_TMP

  if [ -d "$mod_name" ]; then
    RUN cd $mod_name
    RUN git fetch -q
  else
    RUN git clone -q $mod_repo
    RUN cd $mod_name
  fi
}

# determine module diff (commits ahead/behind) against its upstream:
mframe_modules_upstream_diff() {
  if $mod_local; then
    return 0
  fi

  RUN git subrepo branch --fetch --force -q $mod_dir

  mod_local_commit=$(git rev-parse subrepo/$mod_dir)
  mod_ahead=$(git rev-list --count FETCH_HEAD..$mod_local_commit)
  mod_behind=$(git rev-list --count $mod_local_commit..FETCH_HEAD)
}

# list all modules with uncommitted changes:
mframe_modules_list_uncommitted() {
  local mod=

  for mod in $(find $MODULES_DIR -type d -depth 1); do
    if [ ! -f "$mod/.gitrepo" ]; then
      continue
    fi

    if ! git diff --quiet $mod || ! git diff --cached --quiet $mod; then
      echo $mod
    fi
  done
}

# publish current module (manual mode):
# $1 - version to publish
mframe_modules_publish_manual() {
  local v="${1:-$mod_version}"
  local branch="v$(echo $v | sed 's/\.[^.]*$//' | sed 's/\.0$//')"

  # do the work on a temp branch for easy error recovery:
  mframe_utils_git_create_temp_branch

  # in case of any errors remove temp branch and restore initial state:
  trap 'mframe_utils_git_merge_temp_branch' ERR INT

  RUN git subrepo push $mod_dir -b $branch -u -q

  # merge changes made on the temp branch and discard it:
  mframe_utils_git_merge_temp_branch

  publish_success=true
  publish_branch=$branch
}

# publish current module (auto mode):
mframe_modules_publish_auto() {
  # do the work on a temp branch for easy error recovery:
  mframe_utils_git_create_temp_branch

  # in case of any errors remove temp branch and restore initial state:
  trap 'mframe_utils_git_remove_temp_branch' ERR INT

  # push the module changes to a temporary branch, unless this is the first push
  # in which case we push directly on "v1":
  local temp_branch="$git_temp_branch"
  if $mod_local; then
    temp_branch="v1"
  fi

  RUN git subrepo push $mod_dir -b $temp_branch -q

  # get the major of the current module version:
  local major="$(echo $mod_version | sed 's/\.[^.]*$//')"

  mframe_modules_get_versions $major

  RUN cd $MODULES_TMP/$mod_name
  RUN git checkout -q $temp_branch

  local release_type="patch"

  if standard-version --dry-run | grep -q "### BREAKING CHANGES"; then
    if [ "$mod_version" == "$mod_latest_version" ]; then
      release_type="major"
    elif [ "$mod_version" == "$mod_latest_version_prefixed" ]; then
      release_type="minor"
    fi

    if [ "$release_type" == "patch" ]; then
      echo
      echo "ATTENTION: It seems you are making a breaking change to a version of"
      echo "the module which cannot have its major/minor version increased. If"
      echo "you publish your changes upstream, you also need to ensure that all"
      echo "applications using this version of the module can handle the"
      echo "changes."
      echo

      if ! mframe_utils_confirm "Do you want to publish?" "y"; then
        if [ "$temp_branch" != "v1" ]; then
          RUN git push -q origin :$temp_branch
        fi
        mframe_utils_git_remove_temp_branch

        return 0
      fi

      echo
    fi
  fi

  RUN standard-version -r $release_type $([ ! -f CHANGELOG.md ] && echo '-f') --silent

  # the tag used to publish:
  local tag=$(git describe --tags)

  # the branch used to publish:
  local branch=$(echo $tag | sed 's/\.[^.]*$//' | sed 's/\.0$//')

  if [ "$branch" != "$temp_branch" ]; then
    RUN git checkout -q $([ "$release_type" != "patch" ] && echo '-b') $branch

    if [ "$release_type" == "patch" ]; then
      RUN git pull -q
    fi

    RUN git merge -q $temp_branch
    RUN git push -q origin :$temp_branch
    RUN git branch -q -D $temp_branch
  fi

  say git push -u -q --follow-tags origin $branch "> /dev/null"
  git push -u -q --follow-tags origin $branch > /dev/null

  # merge changes made on the temp branch and discard it:
  mframe_utils_git_remove_temp_branch

  RUN cd $ROOT_DIR
  RUN git subrepo clone $mod_repo $mod_dir -b $branch -f -q

  publish_success=true
  publish_branch="$branch"
}

#
# ------------------------------------------------------------------------------
#

# get user input:
# $1 - prompt message
# $2 - default value
# $3 - required flag (true/false, default false)
mframe_utils_input() {
  local REPLY=

  while
    read -p "$1$(if [ ! -z "$2" ]; then echo " [$2]"; fi) "

    if [ ! -z "$REPLY" ]; then
      REPLY=$(sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' <<< $REPLY)
    else
      if [ ! -z "$2" ]; then
        REPLY="$2"
      fi
    fi

    [ -z "$REPLY" ] && [ "$3" == "true" ]
  do
    continue
  done

  RES="$REPLY"
}

# get user confirmation:
# $1 - message/question to display
# $2 - default option (y/n or empty for no default)
mframe_utils_confirm() {
  local res_regex="^([yY]([eE][sS])?|[nN][oO]?)$"
  local res=

  if [ "$AUTOCONFIRM" == "yn" ]; then
    res="$2"
  else
    res="$AUTOCONFIRM"
  fi

  local default=
  if [ "$2" == "y" ]; then
    default=" (Y/n)"
  elif [ "$2" == "n" ]; then
    default=" (y/N)"
  fi

  while ! [[ "$res" =~ $res_regex ]]; do
    read -p "$1$default " res

    if [ -z "$res" -a ! -z "$2" ]; then
      res="$2"
    fi
  done

  if [[ "$res" =~ ^[yY]([eE][sS])?$ ]]; then
    return 0
  else
    return 1
  fi
}

# show an error message and exit:
# $1 - error message
mframe_utils_error() {
  echo "ERROR: $1"
  exit 1
}

# stash/unstash changes in a GIT working directory:
mframe_utils_git_stash_push() {
  if [ "$git_stashed" == "y" ]; then
    return 1
  fi

  mframe_utils_ensure_root_dir

  if ! git diff --quiet || ! git diff --cached --quiet; then
    RUN git stash -q
    git_stashed="y"
  fi
}

mframe_utils_git_stash_pop() {
  if [ "$git_stashed" == "n" ]; then
    return 0
  fi

  mframe_utils_ensure_root_dir

  RUN git stash pop --index -q
  git_stashed="n"
}

# create/merge/remove a temp GIT branch:
mframe_utils_git_create_temp_branch() {
  mframe_utils_ensure_root_dir

  git_temp_branch=temp_$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 4 | head -n 1)
  git_main_branch=$(git rev-parse --abbrev-ref HEAD)

  mframe_utils_git_stash_push
  RUN git checkout -q -b $git_temp_branch
}

mframe_utils_git_merge_temp_branch() {
  mframe_utils_ensure_root_dir

  RUN git checkout -q $git_main_branch
  RUN git merge -q $git_temp_branch

  mframe_utils_git_remove_temp_branch
}

mframe_utils_git_remove_temp_branch() {
  mframe_utils_ensure_root_dir

  RUN git checkout -q $git_main_branch
  RUN git branch -q -D $git_temp_branch
  mframe_utils_git_stash_pop

  git_temp_branch=
  git_main_branch=
}

# ensure we are in the ROOT_DIR directory:
mframe_utils_ensure_root_dir() {
  if [ "$(pwd)" != "$ROOT_DIR" ]; then
    RUN cd $ROOT_DIR
  fi
}

#
# ------------------------------------------------------------------------------
#

RUN() {
  say "$*"
  "$@"
}

say() {
  [ "$CLI_DEBUG" == "true" ] && echo '>>>' "$@"
  return 0
}
