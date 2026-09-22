# claude-emacs

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) inside
Emacs, one session per project, in a real terminal buffer.

`claude-emacs` wraps the `claude` CLI in a [vterm](https://github.com/akermu/emacs-libvterm)
buffer so you get full TUI fidelity (colors, live redraws, the interactive
prompt) rather than reimplementing Claude Code's UI in Elisp. Sessions are
keyed by project root, so each project gets its own persistent buffer that
you can show, hide, and feed context to independently of other projects.

## Installation

Requires Emacs 28.1+, [vterm](https://github.com/akermu/emacs-libvterm)
(which compiles a small native module on install), and the `claude` CLI
on your `PATH`. `transient` is required too but ships with Emacs 28+.

Using `use-package` with `:vc` (Emacs 30+) or `straight.el`:

```elisp
(use-package claude-emacs
  :vc (:url "https://github.com/victorkrassovsky/claude-emacs" :branch "main")
  :bind-keymap ("C-c C-'" . claude-emacs-command-map))
```

Or manually: clone this repo, add it to your `load-path`, and:

```elisp
(require 'claude-emacs)
(keymap-set global-map "C-c C-'" claude-emacs-command-map)
```

## Usage

Bind `claude-emacs-command-map` to a prefix of your choice (`C-c C-'` above),
or bind individual commands directly. All commands operate on the Claude
Code session for the current project (as determined by `project.el`),
starting one if it doesn't exist yet.

| Key | Command                         | Description                                   |
|-----|----------------------------------|------------------------------------------------|
| `o` | `claude-emacs-toggle`            | Show/hide the session window                   |
| `s` | `claude-emacs-start`              | Start or switch to the session (`C-u` for new) |
| `S` | `claude-emacs-start-new-session`  | Kill and restart the session                   |
| `b` | `claude-emacs-switch-to-buffer`   | Switch to the raw session buffer               |
| `k` | `claude-emacs-kill`               | Kill the session                                |
| `c` | `claude-emacs-interrupt`          | Send Escape to interrupt Claude                |
| `r` | `claude-emacs-send-region`        | Send the active region, annotated with file:line |
| `f` | `claude-emacs-send-file-reference`| Insert an `@file` reference into the prompt    |
| `m` | `claude-emacs-send-command`       | Prompt for text and submit it immediately      |
| `t` | `claude-emacs-transient`          | Open a transient menu of the above             |

Sent text (region, file references) is inserted into the prompt but **not**
submitted automatically, so you can compose a multi-part message before
pressing `RET` yourself. `claude-emacs-send-command` is the exception — it
submits immediately, for quick one-off instructions.

## Configuration

```elisp
(setq claude-emacs-program "claude")           ; executable to launch
(setq claude-emacs-program-switches '("--continue"))
(setq claude-emacs-window-side 'right)         ; 'left, 'right, 'top, 'bottom
(setq claude-emacs-window-size 0.4)            ; fraction of frame
(setq claude-emacs-kill-buffer-on-exit nil)    ; keep scrollback after exit
```

## Development

Run the test suite (does not require `vterm` to be installed, since the
tests only cover session bookkeeping, not actual terminal I/O):

```sh
emacs -Q --batch -L . -L test -l claude-emacs-test -f ert-run-tests-batch-and-exit
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
