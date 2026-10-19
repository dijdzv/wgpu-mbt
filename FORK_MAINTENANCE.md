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
