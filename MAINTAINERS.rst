Notes for maintainers.

Versioning
----------

The project version is declared once, in the ``[workspace.package]`` table of
the root ``Cargo.toml``. Both crates inherit it with ``version.workspace =
true``, and ``pyproject.toml`` declares ``dynamic = ["version"]`` so maturin
reads the same value at build time. Bump it there and nowhere else, then run
``cargo build`` (or ``cargo update -w``) so ``Cargo.lock`` records the new
crate versions. Commit both files together: the wheel build runs cargo with
``--locked`` and fails on a stale lockfile.

Cargo uses semver pre-release syntax and maturin converts it to PEP 440 for
the wheel, so one source produces both spellings:

================  ==============  ====================
Cargo.toml        Python / PyPI   Meaning
================  ==============  ====================
``2.0.0-alpha1``  ``2.0.0a1``     first alpha of 2.0.0
``2.0.0``         ``2.0.0``       release
``2.0.99``        ``2.0.99``      main branch after cutting ``v2.0-branch``
================  ==============  ====================

``west.manifest.SCHEMA_VERSION`` in ``src/west/manifest.py`` is the logical
manifest schema version. Update it only when a release introduces manifest
syntax that earlier west versions cannot parse; see "Cutting a release branch"
below.

Continuous integration
----------------------

All workflows live in ``.github/workflows/``. The ones that matter for a
release:

``test.yml``
  Builds one ``abi3`` wheel per OS (Linux, macOS, Windows) with ``uv build``,
  then installs that prebuilt wheel in a matrix of Python 3.10 through 3.14
  and runs the ``poe`` tasks against it. The wheel is compiled at
  ``opt-level = 0`` to keep the job fast; it is never published. Lint and
  format checks run in a separate job that does not compile anything.
  Coverage goes to Codecov.

``test-distros.yml``
  Runs the suite inside containers for Arch, Debian stable and testing,
  Fedora latest and rawhide, openSUSE Tumbleweed, and the Ubuntu development
  release. It runs on ``workflow_dispatch`` and on pull requests that modify
  the workflow itself; trigger it by hand before a release.

``wheels.yml``
  Builds the distribution packages: the sdist plus one optimized ``abi3``
  wheel for each of Linux x86_64 and aarch64 (manylinux and musllinux), macOS
  x86_64 and arm64, and Windows x64 and arm64. Each wheel is built on a native
  runner with `cibuildwheel <https://cibuildwheel.pypa.io/>`_, using the
  ``[tool.cibuildwheel]`` settings in ``pyproject.toml``, then repaired,
  audited for abi3 compliance, and smoke-tested in a fresh virtual
  environment. Follow-up jobs run ``twine check``, verify that every file
  carries the same version (and that it matches the tag, when run on one),
  build a wheel from the sdist, and run the full pytest suite against the
  release wheels. Runs on ``v*`` tags, on pull requests that touch packaging
  inputs, on demand, and when called from ``release.yml``. It never publishes.

``release.yml``
  The only workflow that publishes, and it is manual: run it from the Actions
  tab on a release tag and choose ``testpypi`` or ``pypi``. It calls
  ``wheels.yml``, so nothing is uploaded unless every build, check, and test
  passed, then publishes through trusted publishing (OIDC, no stored
  credentials). Publishing to PyPI requires a ``v*`` tag and runs in the
  ``release`` environment, whose required reviewers must approve the upload.
  For PyPI it also signs a build-provenance attestation for the artifacts,
  recorded in the repository's attestation store, and creates the GitHub
  release for the tag with generated notes, the artifacts, and the
  attestation bundle. Verify a downloaded file with
  ``gh attestation verify <file> --repo <owner>/<repo>``.

  One-time setup lives outside the repository: the ``release`` and
  ``testpypi`` environments (with required reviewers on ``release``) and a
  trusted publisher on each index pointing at ``release.yml`` and the
  matching environment name.

``codeql.yml``, ``scorecards.yml``, ``dependency-review.yml``
  Security scanning. Third-party actions are pinned to commit SHAs; keep that
  policy when touching workflows.

Pre-release test plan
---------------------

0. If no release branch exists, fork the version numbers in the release branch
   (vX.Y-branch) and the main branch. See "Cutting a release branch", below,
   for details.

   The rest of these steps should be done in the release branch::

     git checkout vX.Y-branch

1. Make testing happy on the following first-party non-Linux platforms:

   - Windows 10 or 11
   - the latest macOS

   Do this by hand and check for any anomalous warnings in the output.
   Do not just trust CI. Run both suites::

     cargo test --workspace
     uv run poe all

2. Make testing happy on other popular Linux distributions by dispatching the
   ``test-distros.yml`` workflow on the release branch from the GitHub Actions
   tab.

3. Build alpha N (N=1 to start, then N=2 if you need more commits, etc.) by
   setting the version in ``Cargo.toml`` to ``X.Y.0-alphaN``, tagging, and
   running the ``Release`` workflow on the tag. See "Publishing a release"
   below. Publish to TestPyPI first and install from there on one platform
   before publishing the alpha to PyPI.

4. Install the alpha on test platforms. ::

     pip3 install west-rs==X.Y.0aN

   On platforms without a prebuilt wheel this compiles from the sdist; confirm
   that works too, since end users on those platforms will hit the same path.

5. Create and update a default (Zephyr) workspace on all of the platforms from
   1., using the installed alpha::

     west init -u https://github.com/zephyrproject-rtos/zephyr zephyrproject
     cd zephyrproject
     west update

   Make sure zephyrproject/zephyr has a branch checked out that matches the
   default branch used by zephyr itself.

6. Do the following Zephyr specific testing in the Zephyr workspace on all of
   the platforms from 1. These are extension commands, so they exercise the
   Rust-to-Python dispatch path as well as the Zephyr code. Skip QEMU tests on
   non-Linux platforms, and make sure ZEPHYR_BASE is unset in the calling
   environment. ::

     west build -b qemu_x86 -s zephyr/samples/hello_world -d build-qemu-x86
     west build -d build-qemu-x86 -t run

     west build -b qemu_cortex_m3 -s zephyr/samples/hello_world -d build-qemu-m3
     west build -d build-qemu-m3 -t run

     # This example uses a Nordic board. Do this for as many boards
     # as you have access to / volunteers for.
     west build -b nrf52dk/nrf52832 -s zephyr/samples/hello_world -d build-nrf52
     west flash -d build-nrf52
     west debug -d build-nrf52
     west debugserver -d build-nrf52
     west attach -d build-nrf52

   (It's still a pass if ``west build`` requires ``--pristine``.)

7. If you have a v1 workspace around, run ``west config migrate`` in it and
   check that ``west list`` and ``west update`` behave the same before and
   after. This is the path every existing user takes once.

8. Assuming that all went well (if it didn't, go fix it and repeat):

   - set the version in ``Cargo.toml`` to ``X.Y.Z`` (drop the ``-alphaN``
     suffix), update ``Cargo.lock``, commit

   - tag the release (see "Tagging the release")

   - run the ``Release`` workflow on the tag (see "Publishing a release")

9. Send email to the Zephyr lists, announce@ and users@, notifying them of the
   new release. Include ``git shortlog`` data of the new commits since the last
   release to give credit to all contributors.

Tagging the release
-------------------

Create and push a GPG signed tag. ::

  git tag -a -s vX.Y.Z -m 'West vX.Y.Z

  Signed-off-by: Your Name <your.name@example.com>'

  git push origin vX.Y.Z

Publishing a release
--------------------

Releases are built and uploaded by GitHub Actions, and only on request:

1. Push the signed tag (see "Tagging the release"). Pushing a ``v*`` tag
   already runs ``wheels.yml``, so the build and test results are visible
   before anything is published.

2. Open the ``Release`` workflow in the Actions tab, click "Run workflow",
   select the tag as the ref, and choose ``testpypi``. Check the result at
   https://test.pypi.org/project/west-rs/ and try an install from it::

     pip3 install --index-url https://test.pypi.org/simple/ west-rs==X.Y.Z

3. Run the workflow again on the same tag with ``pypi``. The build repeats,
   the ``publish`` job waits for an approval from the ``release``
   environment's reviewers, then uploads to PyPI, signs a build-provenance
   attestation for the artifacts, and creates the GitHub release with the
   artifacts and the attestation bundle attached. Tags with a hyphenated
   suffix (``v2.0.0-alpha1``) are marked as pre-releases.

If the GitHub release needs editing afterwards (notes, title), edit it in the
web UI; the artifacts stay attached.

To build the wheels locally, for example to inspect them before tagging, use
the same cibuildwheel configuration CI uses::

  scripts/build-wheels.sh --platform macos
  scripts/build-wheels.sh --platform linux

The script copies the tree to a scratch directory without ``target/`` or
``.venv/`` and writes the finished wheels to ``wheelhouse/``. Linux builds
need a running Docker daemon; macOS builds need the python.org CPython 3.10
installer (see the script header). For just the sdist, ``uv build --sdist`` in
a clean tree is enough. Verify a wheel::

  pip3 install -U wheelhouse/west_rs-*.whl
  west --version
  python3 -c 'import west.version; print(west.version.__version__)'

Both should print the version from ``Cargo.toml``, the first in Cargo form
and the second in PEP 440 form. Do not upload by hand with ``twine``: that
bypasses the build checks, the approval gate, and the attestations the
workflow produces.

Cutting a release branch
------------------------

This is how to cut a new release branch for minor version vX.Y.

Summary of what happens:

- before:

  - vX.Y-branch does not exist
  - main branch is at version X.(Y-1).99

- after:

  - vX.Y-branch exists and is at version X.Y.0-alpha1
  - main is at version X.Y.99
  - west.manifest.SCHEMA_VERSION may be updated

1. Check the git logs since the last release::

     git log vX.(Y-1).99..origin/main

   Decide if west.manifest.SCHEMA_VERSION needs an update:

   - SCHEMA_VERSION should be updated to X.Y if release vX.Y will have manifest
     syntax changes that earlier versions of west cannot parse. The version
     check causes earlier west versions to abort and forces users to upgrade
     west to use manifests with new syntax or features.

   - SCHEMA_VERSION should *not* be changed for west vX.Y if the manifest
     syntax is fully compatible with what west vX.(Y-1) can handle. This would
     force some users to upgrade west unnecessarily when trying to use
     manifests wrongly presenting themselves as using new syntax/features that
     have not actually changed.

   If you want to change SCHEMA_VERSION, send this as a pull request to the
   main branch and get it reviewed and merged. (This requires a PR and review
   even though the rest of the steps don't.)

   Note that the Rust core currently parses ``manifest.version`` but does not
   yet reject versions outside the supported window; ``TODO.md`` tracks this.
   Until that lands, a SCHEMA_VERSION bump only affects the Python API.

   **Don't** introduce incompatible manifest changes in patch versions.
   That violates semantic versioning. Example: if v2.1.3 can parse a manifest,
   v2.1.2 should be able to parse it, too, and with the same results.

2. Create and push the release branch for minor version vX.Y.0, which is named
   "vX.Y-branch"::

      git checkout -b vX.Y-branch origin/main
      git push origin vX.Y-branch

   This should already contain the SCHEMA_VERSION change if one is needed.

   Subsequent fixes for patch versions vX.Y.Z should go to vX.Y-branch after
   being backported from main (or the other way around in case of an urgent
   hotfix).

3. In vX.Y-branch, set the version in ``Cargo.toml`` to ``X.Y.0-alpha1``,
   update ``Cargo.lock``, and push to origin/vX.Y-branch. You don't need a PR
   for this.

4. In the main branch, set the version in ``Cargo.toml`` to ``X.Y.99``, update
   ``Cargo.lock``, and push to origin/main. You don't need a PR for this.

5. Create an annotated tag vX.Y.99 which points to the main branch commit you
   just created in the previous step. Push it to origin/main. You don't need a
   PR for this. (This makes ``git describe`` output easy to read during
   development.)

From this point forward, the main branch is moving independently from the
release branch. Do the release prep work in the release branch.

Dependencies
------------

- Rust dependencies are pinned by ``Cargo.lock``, and the wheel build runs
  cargo with ``--locked`` so an sdist install gets exactly the audited crate
  versions. Update them deliberately with ``cargo update`` and run both test
  suites.
- The minimum supported Rust version is ``rust-version`` in ``Cargo.toml``.
  Raising it is a user-visible change for anyone installing from source;
  mention it in the release notes.
- On macOS, ``_build_backend.py`` and the ``poe build`` task set
  ``CARGO_PROFILE_RELEASE_STRIP=none``. Older rustc releases strip debug info
  with a tool that leaves dylibs unloadable on macOS 27 (rust-lang/rust#157750,
  fixed upstream in mid-2026). Once the minimum supported Rust version is past
  the fix, both settings can go.
- Python development dependencies are pinned by ``uv.lock``; the Python
  package itself has no runtime dependencies.
- The PyO3 version is pinned in ``crates/west-cli/Cargo.toml`` with the
  ``abi3-py310`` feature. Changing the abi3 floor changes which Pythons the
  wheel supports; keep it in step with ``requires-python`` in
  ``pyproject.toml`` and the classifiers.
