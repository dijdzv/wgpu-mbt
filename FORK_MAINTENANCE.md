# Fork maintenance

This fork is maintained at `dijdzv/wgpu-mbt`. Its upstream is
`moonbit-community/wgpu-mbt`; the existing package identity is
`Milky2018/wgpu_mbt`.

## Upstream updates

Review upstream changes weekly and before adopting a new upstream release.
This is a maintenance cadence, not an installed automated schedule.

1. Fetch `upstream` and inspect changes since the last integrated upstream commit.
2. Merge the selected upstream commit into a separate integration branch based
   on this fork's `main`. Do not reset or force-push away fork changes.
3. Check whether upstream has replaced any fork changes. Remove redundant
   changes while retaining their purpose and validation history.
4. Run the checks appropriate to the changes, including native platform checks
   when applicable. Record unavailable environments and unverified behavior.
5. Integrate into the fork's `main` only after review and validation.

Keep fork-specific changes small and separate from upstream integration commits.
Retain existing proposal branches until their work is integrated or explicitly
retired. Upstream proposals are submitted by the repository owner.

## Downstream use

Consumers should pin a validated fork commit rather than follow a moving branch.
Updating this fork does not automatically update a consumer's dependency pin.
Reconcile existing consumer-side patches before switching its source, so a fix
is neither dropped nor applied twice.

Keep generally useful binding changes here. Application-specific ownership and
shutdown policy belong in the consumer unless they are part of the binding's
documented contract. A fork does not remove the need to review public API and
resource-lifetime changes.

## Native prebuild module format

The Node prebuild entry `build.cjs` and its release helper
`scripts/wgpu_native_release.cjs` explicitly use CommonJS. Moon dependency trees
can inherit an application's `package.json` module type; consumers should not
need to add a CommonJS package marker to run this prebuild.

Run `node --test scripts/prebuild_scope.test.cjs` to check both ESM and CommonJS
consumer scopes, including the helper's command-line entry. The test uses dynamic
link configuration to avoid downloading native assets; it does not prove native
compilation or GPU behavior. The package-content check retains both required
`.cjs` files in the publish archive. On Windows, the packaged files have also been
checked and compiled, statically linked and minimally executed with both parent
module types; this limited check does not create a GPU device or window.
