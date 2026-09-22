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

`vterm` isn't on GNU ELPA, so make sure MELPA is configured first:

```elisp
(require 'package)
(add-to-list 'package-archives '("melpa" . "https://melpa.org/packages/"))
(package-initialize)
```

**Recommended: `package-vc-install`** (built into Emacs 29+, no extra package
manager needed, and doesn't depend on your `use-package` build including the
optional `:vc` keyword support — that keyword lives in a separate
`use-package-vc.el` file that not every Emacs distribution ships):

```elisp
(use-package vterm
  :ensure t)

(unless (package-installed-p 'claude-emacs)
  (package-vc-install "https://github.com/victorkrassovsky/claude_emacs"))

(use-package claude-emacs
  :after vterm
  :bind-keymap ("C-c C-'" . claude-emacs-command-map))
```

To upgrade later: `M-x package-vc-upgrade RET claude-emacs`.

**If your Emacs's `use-package` does bundle `use-package-vc`**, you can use
`:vc` directly instead:

```elisp
(use-package claude-emacs
  :vc (:url "https://github.com/victorkrassovsky/claude_emacs" :branch "main")
  :bind-keymap ("C-c C-'" . claude-emacs-command-map))
```

If you see `Unrecognized keyword: :vc`, your build doesn't have
`use-package-vc.el` — fall back to the `package-vc-install` method above.

**Using `straight.el`:**

```elisp
(straight-use-package 'vterm)
(straight-use-package
 '(claude-emacs :type git :host github :repo "victorkrassovsky/claude_emacs"))
(require 'claude-emacs)
(keymap-set global-map "C-c C-'" claude-emacs-command-map)
```

**Manually:** clone this repo, add it to your `load-path`, and:

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
