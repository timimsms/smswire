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

- Confirm open decisions 4 to 6 in `docs/SPEC.md`.
- Review the known limitations in `CHANGELOG.md` and `docs/SPEC.md`.
- Try the getting-started guide in a new Rails app against a real provider
  account, including a STOP reply and a delivery status callback.

## Each release

1. Open a pull request that:
   - updates `lib/smswire/version.rb`;
   - in `CHANGELOG.md`, moves the `[Unreleased]` entries under a new
     `[X.Y.Z] - YYYY-MM-DD` heading, leaves `[Unreleased]` empty, and updates
     the compare links at the bottom.
2. Merge it once CI is green.
3. In GitHub, open **Actions > Release > Run workflow** on `main`.
4. The workflow runs the tests, then `rake release` builds the gem, creates
   and pushes the `vX.Y.Z` tag, and publishes with trusted publishing. It
   waits until the version is available on RubyGems.
5. Create a GitHub release from the new tag with the changelog section:

   ```
   gh release create vX.Y.Z --notes-file <(sed -n '/^## \[X.Y.Z\]/,/^## \[/p' CHANGELOG.md | sed '$d')
   ```

If the workflow fails before publishing, fix the problem and run it again;
`rake release` skips tagging when the tag already exists.

## If a release goes wrong

`gem yank smswire -v X.Y.Z` removes a version from installs, but the version
number cannot be reused. Fix forward with a patch release.
