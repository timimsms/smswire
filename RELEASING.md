# Releasing

Releases publish to RubyGems from GitHub Actions with
[trusted publishing](https://guides.rubygems.org/trusted-publishing/), so no
API key or one-time code is stored anywhere. The gem requires MFA for
manual pushes.

## One-time setup

1. On rubygems.org, open the `smswire` gem, then **Trusted publishers**, and
   add a GitHub Actions publisher:
   - Repository: `timimsms/smswire`
   - Workflow filename: `release.yml`
   - Environment: `rubygems`
2. In the GitHub repository settings, create an environment named
   `rubygems`. Add required reviewers if releases should need approval.

## Before 1.0

- Merge the phase pull requests in order, so `main` holds the release.
- Confirm open decisions 4 to 6 in `docs/SPEC.md`.
- Review the known limitations listed under Phase 6 in `docs/SPEC.md`.
- Try the getting-started guide in a new Rails app against a real provider
  account, including a STOP reply and a delivery status callback.

## Each release

1. Make sure CI is green on `main`.
2. Update `lib/smswire/version.rb`.
3. In `CHANGELOG.md`, rename `[Unreleased]` to the version and the release
   date, and start a new empty `[Unreleased]` section.
4. Commit: `Release vX.Y.Z`.
5. Tag and push:

   ```
   git tag -a vX.Y.Z -m "vX.Y.Z"
   git push origin main vX.Y.Z
   ```

6. The release workflow runs the tests, builds the gem, and pushes it to
   RubyGems. Check https://rubygems.org/gems/smswire afterwards.
7. Create a GitHub release from the tag with the changelog section.

## If a release goes wrong

`gem yank smswire -v X.Y.Z` removes a version from installs, but the version
number cannot be reused. Fix forward with a patch release.
