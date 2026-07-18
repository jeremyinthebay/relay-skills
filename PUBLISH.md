# Publishing relay-skills

Two destinations: GitHub (the source of truth) and skills.sh (the discovery layer, which reads
straight from GitHub — there's no separate upload).

## a) Push to GitHub

This repo already has a remote configured:

```sh
cd ~/Projects/relay-skills
git remote -v
# origin  https://github.com/jeremyinthebay/relay-skills.git (fetch)
# origin  https://github.com/jeremyinthebay/relay-skills.git (push)
```

So publishing to GitHub is just:

```sh
cd ~/Projects/relay-skills
git add -A
git commit -m "<describe what changed>"
git push origin main
```

If the remote is ever missing (e.g. a fresh clone, or the GitHub repo hasn't been created yet):

1. Create an empty repository on GitHub first — **a human does this** (`gh repo create
   jeremyinthebay/relay-skills --public --source=. --remote=origin` if `gh` is authenticated, or
   create it in the GitHub UI). This step is not something to hand to an agent with credentials.
2. Then wire it up locally and push:

```sh
cd ~/Projects/relay-skills
git remote add origin https://github.com/jeremyinthebay/relay-skills.git
git branch -M main
git push -u origin main
```

The repo must be **public** for `npx skills add` / skills.sh to be able to read it.

## b) skills.sh

skills.sh has **no submission form and no manual review queue.** It is a leaderboard driven
entirely by anonymous CLI telemetry, layered on top of public GitHub repos (confirmed from
`skills.sh/docs` and `skills.sh/docs/faq`, July 2026):

- Any public GitHub repo with a `SKILL.md` (at the repo root, or — as here — one per skill
  directory) is a valid, installable skill source the moment it's public on GitHub. There's
  nothing to "submit."
- Anyone (including you) installs it with:

  ```sh
  npx skills add jeremyinthebay/relay-skills
  # or a single skill:
  npx skills add jeremyinthebay/relay-skills/skills/parallel-build-serialized-merge
  ```

- **The leaderboard/listing is populated by install telemetry from that command** — when the
  `skills` CLI runs an install, it anonymously reports the `owner/repo` (or `owner/repo/path`)
  installed, in aggregate, with no personal data. There is no login, no dashboard, and no "publish"
  button on skills.sh itself.

### Concrete steps to get relay-skills discoverable on skills.sh

1. **Push the repo to GitHub as public** (section a, above). This is the only hard requirement.
2. **Seed the telemetry yourself**, once, from a machine with the CLI:

   ```sh
   npx skills add jeremyinthebay/relay-skills
   ```

   This is the same command anyone else would run to install it, and it's what makes the repo
   start showing up in aggregate install-count telemetry. (Optional — the repo is technically
   installable by anyone the moment it's public, with or without this step — but running it once
   yourself is the closest thing to a "first listing" action, and it's a genuinely useful sanity
   check that the repo installs cleanly.)
3. **Add the install-count badge to `README.md`** (documented at `skills.sh/docs`), so visitors
   land on the live count:

   ```md
   [![skills.sh](https://skills.sh/b/jeremyinthebay/relay-skills)](https://skills.sh/jeremyinthebay/relay-skills)
   ```

4. **Share the repo** — a post, a link, a mention in another skill's README (this repo already
   does this for `obra/superpowers` and `vercel-labs/skills`) — since the leaderboard is purely
   usage-driven, more real installs is the entire ranking mechanism. There is no other lever.
5. **Security audits** (`skills.sh/audits`) are run by the platform itself, not requested by
   authors — nothing to do here beyond keeping the scripts honest, which they already are (no
   secrets in the repo, no network calls beyond the target site/API the user configures).

### What you do NOT need to do

- No account to create on skills.sh.
- No YAML/JSON manifest to submit anywhere outside the repo itself.
- No approval wait — the repo is live the moment it's public and someone runs `npx skills add`
  against it.

If skills.sh changes this process in the future, re-check `https://skills.sh/docs` and
`https://skills.sh/docs/faq` before assuming the above is still current — this was verified
2026-07-17.
