.. image:: https://img.shields.io/pypi/pyversions/west-rs?logo=python
   :target: https://pypi.org/project/west-rs/

.. image:: https://api.securityscorecards.dev/projects/github.com/zephyrproject-rtos/west/badge
   :target: https://scorecard.dev/viewer/?uri=github.com/zephyrproject-rtos/west

.. image:: https://codecov.io/gh/zephyrproject-rtos/west/graph/badge.svg
   :target: https://codecov.io/gh/zephyrproject-rtos/west

This is the Zephyr RTOS meta tool, ``west``.

https://docs.zephyrproject.org/latest/develop/west/index.html

West v2 is a rewrite of west in Rust. It ships as:

- a single native ``west`` binary that implements every built-in command, and
- a Python package, also called ``west``, that provides the extension command
  framework (``west.commands``) and the public Python API (``west.manifest``,
  ``west.configuration``, ``west.util``). The Python package is a thin layer
  over the same Rust core, exposed through a PyO3 extension module.

Both come out of one Cargo workspace and are distributed together in one
wheel. If you are coming from west v1 (the pure-Python implementation), read
`Migrating from west v1`_ below and ``MIGRATION.md`` for the full list of
behavioral differences.

Installation
------------

Using pip::

  pip3 install west-rs

(Use ``pip3 uninstall west-rs`` to uninstall it.)

The distribution is named ``west-rs``, but it is a drop-in replacement for
the v1 ``west`` package: it provides the same ``west`` command and the same
``west`` Python package. Uninstall v1 first (``pip3 uninstall west``); the two
cannot coexist in one environment because they ship the same files.

The wheel contains the ``west`` binary, which pip places on your ``PATH``, and
the Python package. One ``abi3`` wheel covers every supported Python version
(3.10 and newer). When no prebuilt wheel matches your platform, pip builds from
the source distribution, which requires a Rust toolchain (see `Prerequisites`_).

Other ways to install:

- ``uv tool install west-rs`` installs the same wheel into an isolated
  environment managed by `uv <https://docs.astral.sh/uv/>`_. Extension
  commands run in a separate interpreter (see below), so point
  ``WEST_PYTHON`` at that environment's Python, for example
  ``~/.local/share/uv/tools/west-rs/bin/python``, or install west into the
  virtual environment you use for Zephyr instead.
- ``cargo install --path crates/west-cli`` from a checkout builds only the
  ``west`` binary, with no Python dependency at all. All built-in commands
  work.

Extension commands (``west build``, ``west flash``, ...) are Python programs.
The binary runs them with the interpreter named by ``WEST_PYTHON``, else the
active virtual environment's Python, else ``python3`` on ``PATH``, and that
interpreter needs the ``west`` Python package installed.

Basic Usage
-----------

West lets you manage multiple Git repositories under a single directory using a
single file, called the *west manifest file*, or *manifest* for short.
By default the manifest file is named ``west.yml``.
You use ``west init`` to set up this directory, then ``west update`` to fetch
and/or update the repositories named in the manifest.

Example usage with `upstream Zephyr's manifest file
<https://github.com/zephyrproject-rtos/zephyr/blob/main/west.yml>`_::

  mkdir zephyrproject && cd zephyrproject
  west init -u https://github.com/zephyrproject-rtos/zephyr
  west update

What just happened:

- ``west init`` clones the *west manifest repository* given with ``-u``, in
  this case the zephyr repository, into the workspace. The manifest repository
  contains ``west.yml``, a YAML description of the Zephyr installation,
  including Git repositories and other metadata. West records the workspace
  state in a ``.west/`` directory next to it.

- ``west update`` clones the other repositories named in the manifest file,
  creating working trees in the workspace directory ``zephyrproject``.
  Projects are fetched in parallel by default; use ``-j 1`` or ``--raw`` to
  see each Git command's native output in sequence.

There is no default manifest URL: ``-u`` (or its v1 spelling ``-m``) is
required unless you initialize from an existing local manifest repository with
``west init -l``. Use ``--revision`` (``--mr``) to pick a revision of the
manifest repository; if not given, the remote's default branch is used. Use
``--manifest-file`` (``--mf``) to use a manifest file other than ``west.yml``.

West doesn't care if the manifest repository is zephyr or not. You can and are
encouraged to make your own manifest repositories to meet your needs. Manifest
files may be written in YAML, TOML, or JSON; the format is chosen by file
extension.

For more details, see `West (Zephyr's meta-tool)
<https://docs.zephyrproject.org/latest/develop/west/index.html>`_ in the Zephyr
documentation.

Commands
--------

West has multiple sub-commands. After running ``west init``, you can run them
from anywhere under the workspace. The built-in commands are:

============  ===================================================================
``init``      Initialize a west workspace
``update``    Update projects to their manifest revisions
``list``      List projects defined in the manifest
``manifest``  Inspect, validate, resolve, or freeze the workspace manifest
``status``    Show per-project working-tree status across the workspace
``diff``      Show per-project diffs across the workspace
``compare``   Compare each project's state against the manifest
``forall``    Run a shell command in each project
``grep``      Run a grep-like tool in each project (git-grep / ripgrep / grep)
``config``    Read or write west configuration values
``topdir``    Print the top directory of the west workspace
``exec``      Run an external program (useful with aliases)
``help``      Show help for a command, alias, or extension
============  ===================================================================

``west -h`` lists the built-in commands. ``west help`` additionally lists the
extension commands and aliases available in the current workspace. Get help on
any command with ``west <command> -h``; ``west <command> --help`` prints the
longer form.

Commands that touch every project (``update``, ``diff``, ``status``,
``compare``, ``forall``, ``grep``) run in parallel by default and accept ``-j
N`` to control the number of jobs. They write command data to stdout and
everything else (per-project banners, progress bars, summaries, warnings) to
stderr, so redirecting stdout yields clean, machine-readable output.

West is extensible: you can add new commands to west without modifying its
source code. Extension commands are Python classes declared in a
``west-commands`` file (YAML, TOML, or JSON) inside a project. The Rust binary
discovers them and runs each one through the ``west`` Python package. See
`Extensions <https://docs.zephyrproject.org/latest/develop/west/extensions.html>`_
in the documentation for details.

Configuration
-------------

West follows Git-like conventions for configuration: a system file, a per-user
global file, and a per-workspace local file at ``.west/config.toml``, with
local values taking precedence. Configuration files are TOML and keys are
dotted, for example ``manifest.path`` or ``tool.git.fetch.strategy``.

::

  west config list
  west config get manifest.path
  west config set --global update.jobs 4
  west config unset update.jobs

Any command accepts one-off overrides with ``-c NAME=VALUE`` and extra files
with ``--config-file PATH``.

Migrating from west v1
----------------------

West v2 keeps the manifest format, the workspace layout, the Python extension
command API, and the names and meanings of nearly all command-line options.
The changes you are most likely to notice are:

- Configuration files are TOML rather than INI. ``west config migrate``
  converts an existing v1 configuration file to v2 TOML at the same scope and
  leaves the original in place.
- ``west config`` takes an explicit subcommand (``get``, ``set``, ``unset``,
  ``list``, ``migrate``) instead of positional arguments.
- Diagnostics are prefixed ``west: error:`` and ``west: warning:``. Exit codes
  are ``0`` (success), ``1`` (failure), and ``2`` (usage error or unmet
  pre-condition, such as naming an uncloned project).
- ``west -h`` shows built-ins only; ``west help`` shows extensions and aliases.
- ``west selfupdate`` is gone. Upgrade through the package manager you
  installed west with.

``MIGRATION.md`` in this repository lists every known difference, including
Python API changes, with each entry tagged as changed, dropped, or still a gap.

Hacking on West
---------------

This section contains notes for getting started developing west itself.

Repository layout
~~~~~~~~~~~~~~~~~

``crates/west-core``
  Library crate: manifest parsing, import resolution, configuration, workspace
  discovery, and the Git client. No command-line or Python code.

``crates/west-cli``
  The ``west`` binary (``src/bin/west.rs``), the built-in command
  implementations (``src/commands/``), and, behind the ``pyo3`` Cargo feature,
  the ``_west_native`` Python extension module (``src/python/``).

``src/west``
  The Python package. ``manifest.py``, ``configuration.py``, and ``util.py``
  wrap ``_west_native``; ``commands.py`` is the extension command base class;
  ``_dispatch.py`` is the entry point the binary spawns to run an extension.

``tests``
  The active pytest suite. It spawns the compiled ``west`` binary and imports
  the Python package. ``tests-legacy`` holds v1 tests that have not been ported
  yet and is excluded from test discovery.

``_build_backend.py``
  A PEP 517 build backend wrapping `maturin <https://www.maturin.rs/>`_. It
  builds the ``west`` binary and stages it so that the wheel ships both the
  binary and the extension module. ``pyproject.toml`` explains the details.

The project version lives in one place, the ``[workspace.package]`` table of
the root ``Cargo.toml``. Both crates inherit it and ``pyproject.toml`` reads it
at build time.

Prerequisites
~~~~~~~~~~~~~

- A Rust toolchain at or above the ``rust-version`` in ``Cargo.toml``
  (currently 1.93), for example via `rustup <https://rustup.rs/>`_.
- Python 3.10 or newer and `uv <https://docs.astral.sh/uv/>`__. Plain ``pip``
  (25.1 or newer, for dependency groups) works too.
- Git.

Install the Python development dependencies once::

  # Using uv
  uv sync --frozen

  # Using pip, in an active virtual environment
  pip3 install --group dev

Building
~~~~~~~~

Build the binary alone::

  cargo build --release -p west-cli --bin west

The result is ``target/release/west``. For the Python side as well, build both
artifacts with the ``poe`` task used by the tests::

  uv run poe build

This runs the ``cargo build`` above and then ``maturin develop --release``,
which compiles the extension module with the ``pyo3`` feature and installs it
into the active virtual environment. The two builds deliberately use separate
Cargo target directories (``target/`` and ``target/maturin/``) so they do not
invalidate each other's caches.

Editable install
~~~~~~~~~~~~~~~~

To run west "live" from the current source tree as an ordinary installed
package, run this from the top-level directory of the repository::

  pip3 install -e .

This goes through ``_build_backend.py``, so you get both the binary on your
``PATH`` and the Python package. Note that ``maturin develop`` on its own only
installs the extension module, not the binary.

Running the tests
~~~~~~~~~~~~~~~~~

There are two test suites.

Rust unit and integration tests live under ``crates/*/tests`` and in-module
``#[cfg(test)]`` blocks::

  cargo test --workspace

The Python suite under ``tests/`` drives the compiled binary and the Python
API. It needs the artifacts from ``poe build``, which the ``test`` task
depends on::

  # Full check: tests, ruff lint, ruff format, mypy
  uv run poe all

  # Just the pytest suite
  uv run poe test

  # In parallel with pytest-xdist
  uv run poe test-xdist

Use ``poe -h`` to list all tasks. Arguments to a task are forwarded to the
underlying command::

  # One file
  uv run poe test tests/test_manifest.py

  # One test
  uv run poe test tests/test_config.py::test_config_global

  # Tests matching a keyword, without output capture
  uv run poe test -k import --capture=no

The suite locates the binary in this order: the ``WEST_TEST_BIN`` environment
variable, then ``target/release/west``, then ``target/debug/west``. Set
``WEST_TEST_BIN`` to test an installed wheel or a cross-built binary, which is
what CI does.

Linting and formatting
~~~~~~~~~~~~~~~~~~~~~~

Python code is checked with ``ruff`` and ``mypy``::

  uv run poe lint
  uv run poe format
  uv run poe types

Rust code should pass ``cargo fmt --check`` and ``cargo clippy --workspace``;
these are not yet enforced in CI (see ``TODO.md``).

Creating a wheel package
~~~~~~~~~~~~~~~~~~~~~~~~

To build the wheel and the source distribution::

  uv build

This creates ``dist/west_rs-<version>-cp310-abi3-<platform>.whl`` and
``dist/west_rs-<version>.tar.gz``. The wheel is platform-specific because it
contains native code, but a single wheel per platform serves every Python
version from 3.10 up. Install it with::

  pip3 install -U dist/west_rs-*.whl

You can ``pip3 uninstall west-rs`` to remove this wheel before re-installing
the version from PyPI, etc.

The wheels published to PyPI are built with `cibuildwheel
<https://cibuildwheel.pypa.io/>`_ so that they are repaired for broad
compatibility (``manylinux``, ``musllinux``, macOS deployment targets) and
smoke-tested before upload. To produce the same wheels locally::

  scripts/build-wheels.sh --platform macos
  scripts/build-wheels.sh --platform linux      # needs docker
  scripts/build-wheels.sh --only cp310-manylinux_x86_64   # a single wheel

Finished wheels land in ``wheelhouse/``. Linux builds need a running Docker
daemon. macOS builds need the python.org CPython 3.10 installer, because
cibuildwheel compiles against the framework interpreter and will not install
one itself outside CI. The configuration is the ``[tool.cibuildwheel]`` table
in ``pyproject.toml``; ``.github/workflows/wheels.yml`` runs it across all
supported platforms.

Quick install from Git
~~~~~~~~~~~~~~~~~~~~~~

GitHub offers pip the ability to download and install a .zip archive of any
branch, tag, or pull request with a single command. This compiles the Rust
code locally, so it needs a Rust toolchain, and the first build takes a few
minutes. Examples::

  pip3 uninstall west-rs
  # Pull request 830
  pip3 install https://github.com/zephyrproject-rtos/west/archive/pull/830/head.zip
  # Someone's random version
  pip3 install https://github.com/someone_you_trust/west/archive/some_branch_or_tag.zip

Warning: never install software from people or locations you do not trust!
