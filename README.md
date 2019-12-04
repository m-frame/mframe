# M Frame

M Frame is a CLI tool for building modular applications, regardless of the
technology stack that's being used. It does not require any special
infrastructure, except having your codebase managed by [git](https://git-scm.com).

## Getting Started

### System Requirements

  * [make][make]
  * [git-subrepo][git-subrepo] (>= 0.4.0)
  * [perl][perl] or [envsubst][envsubst]
  * [standard-version][standard-version] (optional, see [Module Versioning][versioning])

### Installation

Supposing you have a GIT repository cloned in `my-app` and you want your modules
to live in `my-app/src/modules`, M Frame can be installed using these steps:

Add M Frame as a _subrepo_:
```bash
cd my-app
mkdir -p src/modules
git subrepo clone git@github.com:m-frame/mframe src/modules/mframe
```

Create a `Makefile` in your app's root directory, with at least the following
contents:
```makefile
# M Frame Configuration:
ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

# include M Frame:
include src/modules/mframe/init.mk
```

M Frame is now installed and typing `make help` will show a list of [available
commands](#commands).

### Usage

Suppose your top `Makefile` looks like this:
```makefile
# M Frame Configuration:
ROOT_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
MODULES_GIT := git@github.com:my-company
MODULES_PFX := module-

# include M Frame:
include src/modules/mframe/init.mk
```

The above configuration assumes you host most of your repositories on GitHub,
under the `my-company` account. It also defines a common prefix for naming
your modules, in case you want to use such a naming convention. See the next
section for more information about how to configure M Frame.

Given the above configuration, here's what M Frame will do if you type these
commands:

#### `make module name=module-test`

Will create a module named `module-test` in `src/modules/test` (notice that the
common prefix is removed).

#### `make module-publish name=test`

Will publish the `module-test` module to `git@github.com:my-company/module-test`.

#### `make module-install name=auth`

Will first confirm whether you actually meant `module-auth` or really `auth` and
then install the latest version of the module from `git@github.com:my-company/[module-]auth`.

For more information about these and other commands that you can use, see the
[Commands](#commands) section.

### Configuration

M Frame is configured by the following parameters, which must be defined at the
top of your `Makefile`.

| Param | Description | Required | Default Value |
| - | - | :-: | - |
| `ROOT_DIR` | The absolute path to your application's root directory | `Yes` | n/a |
| `MODULES_DIR` | The relative path (from `${ROOT_DIR}`) to a directory where modules should live | `No` | The directory where M Frame is installed |
| `MODULES_GIT` | The base URL for your GIT repositories; if defined, will be used to infer a module's repository URL from its name | `No` | n/a |
| `MODULES_TPL` | A default module template to be used when creating new modules  | `No` | `blank` |
| `MODULES_PFX` | Common prefix for module names | `No` | `module-` |

## How It Works

A lot of the heavy-lifting is done by the wonderful [git-subrepo][git-subrepo]
tool. M Frame is more or less a wrapper around this tool plus some extra
features.

Each module is in fact a _subrepo_ and managed through git-subrepo.

## Commands

In the commands below, the `name` parameter can be a GIT repository URL, a
module name or a local directory (for installed modules).

### `make module name=...`

Create a new, initially unpublished, module. This command is interactive and will
ask you to provide or confirm the module's name and future upstream repository.

Optionally, you can provide a module template to be used. If the template is a
GIT repository URL, the new module will be created by cloning that repository,
otherwise the template will be expected in `${MODULES_DIR}/.<template-name>`. If
this directory is not found, or no template is provided, a "blank" module will
be created (based on an internal template provided by M Frame).

All files within the newly created module will be parsed and the following
variables will be substituted, if found:

- `${REPO}` with the new module's repository URL
- `${NAME}` with the new module's name
- `${DIR}` with the new module's local directory, relative to `${MODULES_DIR}`

This command will call the `module-created` [lifecycle hook][hooks].

### `make module-install name=... [v=latest]`

Install a module.

This command will call the module's `install` hook as well as the global
`module-cfgadd` and `module-installed` [lifecycle hooks][hooks].

### `make module-update name=...`

Update an installed module by getting any new commits from its upstream, but
without changing its version (see [Module Versioning][versioning]).

If you want to upgrade/downgrade to another version, use the above
`module-install` command.

This command will call the `module-updated` [lifecycle hook][hooks].

### `make module-publish name=... [v=...]`

Publish a module. This command is used to initially publish a module as well as
to publish any subsequent changes.

If the `v`ersion parameter is specified, it is assumed the user manually
controls the versioning. Otherwise, if [standard-version][standard-version] is
available, the (new) version of the module is determined by looking at the
commits that are being published. For more information, please see the
[Module Versioning][versioning] section.

This command will call the `module-published` [lifecycle hook][hooks].

### `make module-remove name=...`

Remove an installed module.

This command will call the module's `remove` hook as well as the global
`module-cfgrem` and `module-removed` [lifecycle hooks][hooks].

### `make module-status [name=...]`

Show brief status information about one or all installed modules. This command
will print the number of commits ahead/behind of the installed module compared
to its published (upstream) version.

### `make module-info [name=...]`

Show more detailed information about one or all installed modules. This command
will print the actual commits a module is ahead or behind its upstream.

## Crash Recovery

A lot of the git-subrepo commands that are used to manage modules require that
your GIT working directory is "clean" (i.e.: there are no uncommitted changes).

Before running module related commands, M Frame checks for uncommitted changes
and stashes them. Further more, any operation that requires a change to your
repository (i.e.: new commits) is performed on a separate temporary branch and
once the command completes successfully that branch is merged into your original
branch.

Recovering from an unexpected crash is therefore pretty simple:

1. Check if the GIT repository is on a temp branch and switch to the original
branch
2. Check if there are any stashed files and unstash them

Following the above 2 steps should bring your repository back to the exact same
state as before executing the command that crashed.

## Extending M Frame

M Frame can be extended through modules by creating a `makefile.mk` file as part
of the module. This file gets loaded by M Frame and its targets become
additional commands that you can execute.

Some examples of modules that extend M Frame range from having cloud deployment
scripts or database management utilities that can be (re)used across multiple
projects.

## Lifecycle Hooks

Using the hooks below, modules can better integrate with the applications they
are installed in and M Frame can better integrate into your workflow.

All hooks are optional.

### Module Hooks

These hooks are implemented in modules.

#### `<module-name>-install`

Called when the module is installed.

#### `<module-name>-remove`

Called just before the module is removed.

### Global Hooks

These hooks should be implemented in your `Makefile` and they are all called
with the following parameters:

- `repo` the module's repository URL
- `name` the module's name
- `dir` the module's local directory, relative to `${MODULES_DIR}`

#### `module-created`

Called after a new module is successfully created.

#### `module-installed`

Called after a module is installed.

#### `module-cfgadd`

Called after a module is installed. The main purpose of this hook should be to
merge the module's (default) configs into the main app's config. It's a separate
hook from `module-installed` because you might want to call this multiple times
manually.

#### `module-updated`

Called after a module is updated.

#### `module-published`

Called after a module is published.

#### `module-removed`

Called after a module is removed.

#### `module-cfgrem`

Called after a module is removed. The main purpose of this hook should be to
remove the module's configs from the main app's config.

## Module Versioning

If you specify a `v`ersion parameter when publishing your module, M Frame
assumes you want to manually manage versioning and will publish to the specified
version.

If no version is specified and [standard-version][standard-version] is found in
your path, M Frame will try to infer the new module version by looking at your
commit messages (check the documentation of standard-version to learn more about
how this works).

Version numbers look like [semver](https://semver.org) versions, but M Frame
uses these 2 rules:

  1. Non-breaking changes always increase the `patch` number
  2. Breaking changes increase the `major` number if the change happens on the
     latest `major`, the `minor` number if it happens on the latest `minor` or
     the `patch` version in all other cases

### Example

Suppose latest published versions for a module are: `2.0.5`, `1.0.0`, `1.1.6`.

#### Non-breaking Change

  - `2.0.5` -> `2.0.6` (on the same `v2` branch)
  - `1.0.0` -> `1.0.1` (on the same `v1` branch)
  - `1.1.6` -> `1.1.7` (on the same `v1.1` branch)

#### Breaking Change

  - `2.0.5` -> `3.0.0` (on a new `v3` branch)
  - `1.0.0` -> `1.0.1` (on the same `v1` branch)
  - `1.1.6` -> `1.2.0` (on a new `v1.2` branch)

## Contributing

All PRs are welcome!

## People

The author of M Frame is [Catalin Ciocov](https://github.com/cciocov)

## License

[MIT](LICENSE)

[git-subrepo]: https://github.com/ingydotnet/git-subrepo
[make]: https://www.gnu.org/software/make/
[envsubst]: https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html
[perl]: https://perl.org
[standard-version]: https://github.com/conventional-changelog/standard-version
[hooks]: #lifecycle-hooks
[versioning]: #module-versioning
