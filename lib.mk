# string equality:
# usage: $(if $(call eq,str1,str2),true,else)
define eq
$(and $(findstring $1,$2),$(findstring $2,$1))
endef

# get defined targets, optionally excluding hidden ones:
# $1 - exclude hidden
define get_targets
$(shell $(MAKE) -pRrq : 2>/dev/null | awk -v RS= -F: '/^# Implicit Rules/,/^# Finished Make data base/ {if ($$1 !~ "^[#.]") {print $$1}}' | sort | egrep -v $(and $1,-e '^[^[:alnum:]]') -e '^$@$$')
endef

# check if a target exists:
# $1 - target
define is_target
$(filter $1,$(call get_targets))
endef

# print with padding:
# $1 - padding
# $2 - message
define utils_sh_print
printf %$1s $2
endef

# validate a required variable:
# $1 - variable to validate
# $2 - custom error message
define utils_sh_required
if [ -z "$1" ]; then echo ERROR: $(or $2,Missing required parameter.) && false; fi
endef

# get user confirmation:
# $1 - message/question to display
# $2 - default option (y/n or empty for no default)
define utils_sh_confirm
if [ ! -z "$(autoconfirm)" ]; then res="$(autoconfirm)"; else while [ "$$res" != "y" -a "$$res" != "Y" -a "$$res" != "n" -a "$$res" != "N" ]; do read -p "$1 ($$(if [ "$2" = "y" ]; then echo Y/n; elif [ "$2" = "n" ]; then echo "y/N"; else echo y/n; fi)) " res; if [ -z "$$res" -a ! -z "$2" ]; then res="$2"; fi; done; fi && if [ "$$res" = "y" -o "$$res" = "Y" ]; then true; else false; fi
endef

# get user input:
# $1 - prompt message
# $2 - default value
define utils_sh_input
read -p "$1 [$2] " res && if [ ! -z "$$res" ]; then echo $$res; else echo $2; fi
endef

# require we are in a GIT working directory:
define utils_sh_git_required
if [ ! -d .git ]; then echo "ERROR: This command only works inside a GIT working directory." && false; fi
endef

# require we are in a clean GIT working directory:
define utils_sh_git_required_clean
$(call utils_sh_git_required) && if git diff --quiet && git diff --cached --quiet; then true; else echo "ERROR: All changes must be committed or stashed before running this command." && false; fi
endef

# stash/unstash changes in the working directory:
define utils_sh_git_stash
SH_GIT_STASHED=$$([ ! -d .git ] || ((git diff --quiet && git diff --cached --quiet) || (git stash > /dev/null && echo true)))
endef
define utils_sh_git_unstash
if [ "$$SH_GIT_STASHED" = "true" ]; then git stash pop > /dev/null; fi
endef
