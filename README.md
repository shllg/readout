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

Requirements: `bash`, `curl`, `jq`. Make sure `~/.local/bin` is on your `PATH`.

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
readout report.html                       # publish one file, prints the URL
readout ./site --title "Q3 review"        # publish a folder
readout ./site --name branch-review       # same name again replaces the page, same URL
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

Errors go to stderr as `readout: <message>`. Exit codes: 0 success, 1 server or network error,
2 usage error, 3 missing token, `curl` or `jq`.

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
