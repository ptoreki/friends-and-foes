# Publishing Friends & Foes

One `git push --tags` sends a release everywhere players install from:

| Players use | They install from | Set up |
|---|---|---|
| CurseForge app | CurseForge | step 3 |
| WowUp (standard) | Wago | step 4 |
| WowUp-CF | CurseForge | step 3 |
| WowUp "install from URL" | GitHub releases (repo must be **public**) | step 1 |
| Manual download | any of the above | — |

The GitHub Action (`.github/workflows/release.yml`) does these steps:
1. Runs the tests.
2. Checks that the tag matches the version in the `.toc` and `Core.lua`.
3. Builds the zip with the BigWigs packager.
4. Uploads it to CurseForge, Wago and a GitHub release, with `CHANGELOG.md` as the notes. Any
   site whose ID or token isn't set yet is skipped.

## One-time setup

### 1. GitHub
1. Create a repo on github.com. Make it **public** if WowUp users should be able to install it
   straight from GitHub.
2. Push the code:
   ```
   git remote add origin https://github.com/<you>/friends-and-foes.git
   git push -u origin main
   ```
GitHub releases need nothing else; the built-in `GITHUB_TOKEN` is used.

### 2. Add the site IDs to the addon
After steps 3 and 4, add the IDs to `FriendsAndFoes/FriendsAndFoes.toc`, under `## IconTexture`:
```
## X-Curse-Project-ID: 123456
## X-Wago-ID: AbCdEfGh
```
The packager reads these lines to know where to upload.

### 3. CurseForge
1. Go to https://authors.curseforge.com and create a project: World of Warcraft → Addons. Pick
   **WoW Forever** as the game version if it's offered.
2. Copy the **Project ID** from the project page into the `.toc` (step 2).
3. Create an API token at https://authors.curseforge.com/account/api-tokens.
4. Add the token on GitHub: repo → Settings → Secrets and variables → Actions → New repository
   secret. Name it `CF_API_KEY`.

### 4. Wago
1. Go to https://addons.wago.io and create a project with the Forever flavor.
2. Copy its **ID** into the `.toc` (step 2).
3. Create an API token in your Wago account settings.
4. Add it as a GitHub secret named `WAGO_API_TOKEN`.

## Each release
1. Bump the version in **both** `FriendsAndFoes/FriendsAndFoes.toc` (`## Version:`) and
   `FriendsAndFoes/Core.lua` (`ns.VERSION`), plus `package.json`.
2. Add a section at the top of `CHANGELOG.md`.
3. Write 3-8 short patch notes for the new version in `WhatsNew.lua` / `Locale.lua`
   (`L.NEW_<ver>_n`); a test fails without them.
4. Run `npm test`, then commit.
5. Tag and push:
   ```
   git tag v0.5.3
   git push && git push --tags
   ```
5. Watch the run under the repo's **Actions** tab. Players' apps pick up the update within an hour
   or so.

## Notes
- **Game version:** the packager works out the game version from `## Interface: 16001`. If
  CurseForge files the upload under the wrong game version, add `-g <version>` to the packager
  `args` in the workflow (for Forever, the CurseForge version label, e.g. `1.60.1`).
- **Beta / alpha releases:** tag `v0.6.0-beta` (or `-alpha`) to publish a beta (or alpha) file;
  apps only offer those to players who opted in. The version check ignores the suffix, so the `.toc`
  and `Core.lua` stay at `0.6.0`. A plain `v0.6.0` tag is a normal release.
- **Local test zip:** `npm run package` still builds `dist/FriendsAndFoes-<version>.zip`.
