;;; claude-emacs.el --- Integrate Claude Code into Emacs -*- lexical-binding: t; -*-

;; Copyright (C) 2026  Victor Krassovsky

;; Author: Victor Krassovsky <victorkrassovsky@hotmail.com>
;; Maintainer: Victor Krassovsky <victorkrassovsky@hotmail.com>
;; Version: 0.1.0
;; Package-Requires: ((emacs "28.1") (vterm "0.0.2") (transient "0.3.0"))
;; Keywords: tools, convenience, ai
;; URL: https://github.com/victorkrassovsky/claude-emacs

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; claude-emacs runs the Claude Code CLI (`claude') inside a vterm
;; buffer, one per project, and provides commands to toggle its
;; window and feed it context from Emacs buffers.
;;
;; A session is keyed by project root (as determined by `project.el'),
;; so each project gets its own persistent Claude Code buffer that you
;; can show, hide, and send text to independently of other projects.
;;
;; Usage:
;;
;;   (require 'claude-emacs)
;;   (keymap-set global-map "C-c C-'" claude-emacs-command-map)
;;
;; Then, in any project:
;;
;;   C-c C-' o   claude-emacs-toggle            show/hide the session
;;   C-c C-' r   claude-emacs-send-region        send the active region
;;   C-c C-' f   claude-emacs-send-file-reference  insert an @file reference
;;   C-c C-' m   claude-emacs-send-command       send and submit a one-off command
;;   C-c C-' t   claude-emacs-transient          command menu
;;
;; See the README for full documentation.

;;; Code:

(require 'cl-lib)
(require 'project)
(require 'subr-x)
(require 'transient)
(require 'vterm nil t)

(declare-function vterm-mode "vterm")
(declare-function vterm-send-string "vterm")
(declare-function vterm-send-return "vterm")
(declare-function vterm-send-key "vterm")
(defvar vterm-shell)
(defvar vterm-kill-buffer-on-exit)

;;; Customization

(defgroup claude-emacs nil
  "Run Claude Code inside Emacs."
  :group 'tools
  :prefix "claude-emacs-")

(defcustom claude-emacs-program "claude"
  "Executable used to launch Claude Code."
  :type 'string
  :group 'claude-emacs)

(defcustom claude-emacs-program-switches nil
  "List of extra command-line switches passed to `claude-emacs-program'."
  :type '(repeat string)
  :group 'claude-emacs)

(defcustom claude-emacs-window-side 'right
  "Side of the frame on which to display the Claude Code window."
  :type '(choice (const :tag "Right" right)
                  (const :tag "Left" left)
                  (const :tag "Top" top)
                  (const :tag "Bottom" bottom))
  :group 'claude-emacs)

(defcustom claude-emacs-window-size 0.4
  "Size of the Claude Code window, as a fraction of the frame.
Interpreted as a width when `claude-emacs-window-side' is `left' or
`right', and as a height when it is `top' or `bottom'."
  :type 'number
  :group 'claude-emacs)

(defcustom claude-emacs-kill-buffer-on-exit nil
  "Whether to kill a Claude Code buffer when the underlying process exits.
When nil, the buffer (and its scrollback) is left behind for review."
  :type 'boolean
  :group 'claude-emacs)

;;; Internal state

(defvar claude-emacs--sessions (make-hash-table :test #'equal)
  "Hash table mapping project root directories to Claude Code buffers.")

(defvar-local claude-emacs--root nil
  "Project root directory this Claude Code buffer belongs to.")

;;; Session bookkeeping

(defun claude-emacs--project-root ()
  "Return the root directory of the current project.
Falls back to `default-directory' when not inside a recognized project."
  (if-let ((proj (project-current)))
      (expand-file-name (project-root proj))
    (expand-file-name default-directory)))

(defun claude-emacs--session-buffer (root)
  "Return the live Claude Code buffer for ROOT, or nil.
Removes ROOT from the session table if its buffer was killed."
  (let ((buf (gethash root claude-emacs--sessions)))
    (if (and buf (buffer-live-p buf))
        buf
      (remhash root claude-emacs--sessions)
      nil)))

(defun claude-emacs--buffer-name (root)
  "Return the buffer name to use for a Claude Code session rooted at ROOT."
  (format "*claude:%s*" (file-name-nondirectory (directory-file-name root))))

(defun claude-emacs--command-string ()
  "Return the shell command line used to launch Claude Code."
  (mapconcat #'shell-quote-argument
             (cons claude-emacs-program claude-emacs-program-switches)
             " "))

(defun claude-emacs--display-buffer (buffer)
  "Display BUFFER in the configured side window and select it."
  (let ((dimension (if (memq claude-emacs-window-side '(left right))
                        'window-width
                      'window-height)))
    (select-window
     (display-buffer
      buffer
      `((display-buffer-reuse-window display-buffer-in-side-window)
        (side . ,claude-emacs-window-side)
        (slot . 0)
        (,dimension . ,claude-emacs-window-size))))))

(defun claude-emacs--ensure-vterm ()
  "Signal a clear error if the `vterm' package is not available."
  (unless (require 'vterm nil t)
    (user-error "The `vterm' package is required by claude-emacs; please install it")))

(defun claude-emacs--make-session (root)
  "Start a new Claude Code session rooted at ROOT and return its buffer."
  (claude-emacs--ensure-vterm)
  (let* ((default-directory root)
         (buf (generate-new-buffer (claude-emacs--buffer-name root)))
         (vterm-shell (claude-emacs--command-string))
         (vterm-kill-buffer-on-exit claude-emacs-kill-buffer-on-exit))
    (claude-emacs--display-buffer buf)
    (with-current-buffer buf
      (setq default-directory root)
      (vterm-mode)
      (setq claude-emacs--root root))
    (puthash root buf claude-emacs--sessions)
    buf))

(defun claude-emacs--get-or-create-session (root)
  "Return the live Claude Code session buffer for ROOT, creating one if needed."
  (or (claude-emacs--session-buffer root)
      (claude-emacs--make-session root)))

(defun claude-emacs--kill-session (root)
  "Kill the Claude Code session for ROOT, if any."
  (when-let ((buf (claude-emacs--session-buffer root)))
    (remhash root claude-emacs--sessions)
    (let ((kill-buffer-query-functions nil))
      (kill-buffer buf))))

;;; Sending text

(defun claude-emacs--send (string &optional submit)
  "Send STRING to the current project's Claude Code session.
Creates the session if it is not already running.  When SUBMIT is
non-nil, also sends return to submit the prompt."
  (let* ((root (claude-emacs--project-root))
         (buf (claude-emacs--get-or-create-session root)))
    (with-current-buffer buf
      (vterm-send-string string)
      (when submit
        (vterm-send-return)))
    (claude-emacs--display-buffer buf)))

;;; Commands

;;;###autoload
(defun claude-emacs-start (&optional new-session)
  "Start or switch to the Claude Code session for the current project.
With a prefix argument NEW-SESSION, kill any existing session for
this project first and start a fresh one."
  (interactive "P")
  (let ((root (claude-emacs--project-root)))
    (when (and new-session (claude-emacs--session-buffer root))
      (claude-emacs--kill-session root))
    (claude-emacs--display-buffer (claude-emacs--get-or-create-session root))))

;;;###autoload
(defun claude-emacs-start-new-session ()
  "Kill any existing Claude Code session for this project and start fresh."
  (interactive)
  (claude-emacs-start t))

;;;###autoload
(defun claude-emacs-toggle ()
  "Toggle the visibility of the Claude Code window for the current project.
Starts a session if none exists yet."
  (interactive)
  (let* ((root (claude-emacs--project-root))
         (buf (claude-emacs--session-buffer root))
         (window (and buf (get-buffer-window buf t))))
    (cond
     (window (delete-window window))
     (buf (claude-emacs--display-buffer buf))
     (t (claude-emacs--display-buffer (claude-emacs--make-session root))))))

;;;###autoload
(defun claude-emacs-switch-to-buffer ()
  "Switch to the Claude Code buffer for the current project."
  (interactive)
  (pop-to-buffer (claude-emacs--get-or-create-session (claude-emacs--project-root))))

;;;###autoload
(defun claude-emacs-kill ()
  "Kill the Claude Code session for the current project, if any."
  (interactive)
  (let ((root (claude-emacs--project-root)))
    (if (claude-emacs--session-buffer root)
        (when (yes-or-no-p (format "Kill Claude Code session for %s? " root))
          (claude-emacs--kill-session root))
      (message "No Claude Code session running for %s" root))))

;;;###autoload
(defun claude-emacs-interrupt ()
  "Send an interrupt (Escape) to the current project's Claude Code session."
  (interactive)
  (let* ((root (claude-emacs--project-root))
         (buf (claude-emacs--session-buffer root)))
    (if buf
        (with-current-buffer buf
          (vterm-send-key "<escape>"))
      (message "No Claude Code session running for %s" root))))

;;;###autoload
(defun claude-emacs-send-region (start end)
  "Send the region between START and END to the Claude Code session.
The text is inserted into the prompt, prefixed with its source file
and line range when available, but not submitted automatically."
  (interactive "r")
  (let* ((text (buffer-substring-no-properties start end))
         (header (when buffer-file-name
                   (format "%s:%d-%d\n"
                           (file-relative-name buffer-file-name
                                                (claude-emacs--project-root))
                           (line-number-at-pos start)
                           (line-number-at-pos end)))))
    (claude-emacs--send (concat header text))))

;;;###autoload
(defun claude-emacs-send-file-reference ()
  "Insert an @-reference to the current file into the Claude Code prompt.
If a region is active, its line range is appended as plain text.  The
prompt is not submitted automatically."
  (interactive)
  (unless buffer-file-name
    (user-error "Buffer is not visiting a file"))
  (let* ((root (claude-emacs--project-root))
         (rel (file-relative-name buffer-file-name root))
         (ref (if (use-region-p)
                  (format "@%s (lines %d-%d) "
                          rel
                          (line-number-at-pos (region-beginning))
                          (line-number-at-pos (region-end)))
                (format "@%s " rel))))
    (claude-emacs--send ref)))

;;;###autoload
(defun claude-emacs-send-command (command)
  "Send COMMAND to the Claude Code session and submit it immediately."
  (interactive "sClaude Code command: ")
  (claude-emacs--send command t))

;;; Keymap and transient menu

(defvar claude-emacs-command-map
  (let ((map (make-sparse-keymap)))
    (define-key map "o" #'claude-emacs-toggle)
    (define-key map "s" #'claude-emacs-start)
    (define-key map "S" #'claude-emacs-start-new-session)
    (define-key map "b" #'claude-emacs-switch-to-buffer)
    (define-key map "k" #'claude-emacs-kill)
    (define-key map "c" #'claude-emacs-interrupt)
    (define-key map "r" #'claude-emacs-send-region)
    (define-key map "f" #'claude-emacs-send-file-reference)
    (define-key map "m" #'claude-emacs-send-command)
    (define-key map "t" #'claude-emacs-transient)
    map)
  "Keymap of `claude-emacs' commands, meant to be bound to a prefix key.")

;;;###autoload (autoload 'claude-emacs-transient "claude-emacs" nil t)
(transient-define-prefix claude-emacs-transient ()
  "Claude Code commands."
  ["Claude Code"
   ["Session"
    ("o" "Toggle window" claude-emacs-toggle)
    ("s" "Start / switch" claude-emacs-start)
    ("S" "Start new session" claude-emacs-start-new-session)
    ("b" "Switch to buffer" claude-emacs-switch-to-buffer)
    ("k" "Kill session" claude-emacs-kill)
    ("c" "Interrupt (Esc)" claude-emacs-interrupt)]
   ["Send"
    ("r" "Send region" claude-emacs-send-region)
    ("f" "Send file reference" claude-emacs-send-file-reference)
    ("m" "Send command" claude-emacs-send-command)]])

(provide 'claude-emacs)
;;; claude-emacs.el ends here
