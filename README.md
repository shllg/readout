# readout

Publish a file or a folder from the command line and get a URL back. Open the URL on your phone,
sign in once, and read the page. Markdown is rendered, Mermaid diagrams included.

This repository is the client: the `readout` CLI, an agent skill, and an installer. The HTTP
contract a server must implement is in [docs/api.md](docs/api.md).

## Install

```sh
git clone https://github.com/shllg/readout && cd readout
./install.sh
```

The installer symlinks the CLI to `~/.local/bin/readout` and the skill to
`~/.claude/skills/readout` and `~/.agents/skills/readout`. Updating is `git pull`. Run
`./install.sh --dry-run` to see what it would do and `./install.sh --uninstall` to remove the
links. It never replaces a file or a symlink it does not own.

Requirements: `bash`, `curl`, `jq`, and one of `sha256sum`, `shasum` or `openssl` (Linux and
macOS ship one). Make sure `~/.local/bin` is on your `PATH`.

## Configure

| Variable | Meaning |
|---|---|
| `READOUT_TOKEN` | Your API key. Required. |
| `READOUT_URL` | Server origin. Must be `https://`; plain `http://` is accepted only for `localhost`, `127.0.0.1` and `[::1]`. Default `https://readout.hillig.dev`. |
| `READOUT_DRY_RUN` | `1` prints the manifest and target instead of sending. |
| `READOUT_CURL` | Path of the `curl` binary to use. Default `curl`. |

The CLI always runs curl with `-q`, so it ignores `~/.curlrc`.

Check the setup with `readout whoami`.

## Use

```sh
readout report.html                       # publish one file and the assets it loads, prints the URL
readout report.html                       # again after an edit: same page, same URL
readout ./site --title "Q3 review"        # publish a folder
readout ./site --name branch-review       # one URL even when the content moves between paths
readout report.html --new                 # a separate page, even for the same path
readout notes.md --ttl 7d                 # expire after 7 days (m, h, d)
readout notes.md --keep                   # never expire
readout publish report.html --json        # full response instead of the URL
readout ls                                # id  expires  title
readout rm <id>                           # delete a page
readout whoami                            # print the account email
readout version
```

Folders are published as they are, with relative links between files. The CLI skips `.git/`,
`node_modules/`, `.DS_Store` and every dotfile, and rejects symlinks that point outside the
folder. File names may contain only `A-Z a-z 0-9 . _ @ + -` and spaces, with at most 8 path
segments.

A single HTML file brings along the assets it loads from its own folder: the relative `src` or
`href` of its `<script>`, `<link>`, `<img>`, `<source>`, `<video>` and `<audio>` tags, for
scripts, styles, images, fonts and media. Links to other documents, external URLs, absolute and
`../` paths, dotfiles and missing files are left out; a reference that cannot be published is
skipped with a warning. The HTML file becomes the entry. To publish linked pages, publish their
folder.

Every publish without `--name` is named after its path: `path:` plus the first 16 hex characters
of `sha256(<host name>:<canonical path>)`. Publishing the same file or folder again replaces the
page, keeps its URL and prints `readout: replaced existing page <id>` on stderr; `--new` starts a
separate page instead.

Errors go to stderr as `readout: <message>`. Exit codes: 0 success, 1 server or network error,
2 usage error, 3 missing token, `curl`, `jq` or SHA-256 tool.

## Skill

`skills/readout/SKILL.md` teaches a coding agent to publish standalone HTML or Markdown documents
with `readout` and hand you the URL. It uses shell commands only, so any agent that reads skills
can use it. The installer links it for Claude Code and for the shared `~/.agents/skills` location.

## Tests

```sh
bash test/cli_test.sh
bash test/install_test.sh
```

The tests run offline against a fake `curl` and a temporary home directory.

## License

MIT. See [LICENSE](LICENSE).
