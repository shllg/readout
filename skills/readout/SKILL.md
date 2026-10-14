---
name: readout
description: Use when you produce a standalone HTML or Markdown document for the user to read that is not part of a git repository (a report, review writeup, analysis, cheatsheet, or plan meant for reading), so the user can open it on a phone or another device. Publishes the file or folder with the `readout` command and returns a URL.
---

# readout

`readout` publishes a file or folder to a private page and prints a URL. The user opens the URL on
any device, signs in once, and reads the document. Markdown is rendered, Mermaid diagrams included.

## When to use

You wrote, or are about to write, a standalone HTML or Markdown document for the user to read, and
it does not belong in a git repository: a report, a review writeup, an analysis, a cheatsheet, or a
plan meant for reading.

Do not use it for files that belong in the project, for source code, or for anything the user
wants kept only on their machine.

## Steps

1. Write the file or folder to a temporary or scratch directory. Prefer one self-contained HTML
   file. If the document has assets, keep them beside the entry file and reference them with
   relative paths. File names may use only `A-Z a-z 0-9 . _ @ + -` and spaces.
2. Publish it:

   ```sh
   readout publish <path> --title "<title>"
   ```

   Add `--name <stable-key>` when the same report will be regenerated, for example one key per
   branch review (`--name review-feature-x`). Publishing again with the same name replaces the
   content and keeps the same URL.
3. Give the URL to the user on its own line. The command prints only the URL on success.
4. If publishing fails, keep the local file, tell the user where it is, and carry on with the main
   task. Publishing must never block the work.

If `readout` is not installed, or `READOUT_TOKEN` is not set, skip publishing: keep the local file
and say that publishing was skipped and why.

## Options

| Flag | Effect |
|---|---|
| `--title T` | Page title. Default: the document's own title. |
| `--entry PATH` | The file to open first, relative to a published folder. Default: chosen by the server (`index.html`, the only `.html`, `index.md`, `README.md`). |
| `--name KEY` | Stable key so a later publish replaces this page and keeps its URL. |
| `--ttl 90m\|12h\|7d` | Keep the page for this long. Default 30 days. |
| `--keep` | Never expire. Cannot be combined with `--ttl`. |
| `--json` | Print the full response instead of the URL. |

Other commands: `readout ls` lists your pages, `readout rm <id>` deletes one, `readout whoami`
checks the token.

## Never publish

Do not publish secrets, credentials, API keys, tokens, or `.env` content. Check the file or folder
before publishing. Ask the user first before publishing anything they marked confidential.

## Example

The user asked for a writeup of a branch review.

```sh
mkdir -p "$(mktemp -d)/review" && cd "$_"   # scratch folder
# ... write index.html here ...
readout publish . --title "Review: feature-x" --name review-feature-x
```

Reply to the user:

> The review is ready to read:
>
> https://readout.example.org/p/Zq3k9T0vWl8xYb2A
