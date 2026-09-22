;;; claude-emacs-test.el --- Tests for claude-emacs -*- lexical-binding: t; -*-

;;; Commentary:

;; ERT tests for the parts of claude-emacs that do not require an
;; actual vterm process (session bookkeeping, naming, command-line
;; construction).  Run with:
;;
;;   emacs -Q --batch -L . -L test -l claude-emacs-test -f ert-run-tests-batch-and-exit

;;; Code:

(require 'ert)
(require 'claude-emacs)

(defmacro claude-emacs-test--with-clean-sessions (&rest body)
  "Run BODY with a fresh, empty `claude-emacs--sessions' table."
  (declare (indent 0))
  `(let ((claude-emacs--sessions (make-hash-table :test #'equal)))
     ,@body))

(ert-deftest claude-emacs-test-buffer-name ()
  (should (equal (claude-emacs--buffer-name "/home/user/projects/foo/")
                  "*claude:foo*"))
  (should (equal (claude-emacs--buffer-name "/home/user/projects/foo")
                  "*claude:foo*")))

(ert-deftest claude-emacs-test-command-string-no-switches ()
  (let ((claude-emacs-program "claude")
        (claude-emacs-program-switches nil))
    (should (equal (claude-emacs--command-string) "claude"))))

(ert-deftest claude-emacs-test-command-string-with-switches ()
  (let ((claude-emacs-program "claude")
        (claude-emacs-program-switches '("--continue" "--model" "opus")))
    (should (equal (claude-emacs--command-string)
                    "claude --continue --model opus"))))

(ert-deftest claude-emacs-test-command-string-quotes-arguments ()
  (let ((claude-emacs-program "/usr/local/bin/claude code")
        (claude-emacs-program-switches nil))
    (should (equal (claude-emacs--command-string)
                    (shell-quote-argument "/usr/local/bin/claude code")))))

(ert-deftest claude-emacs-test-session-buffer-purges-dead-buffers ()
  (claude-emacs-test--with-clean-sessions
    (let ((buf (generate-new-buffer "fake-claude-session")))
      (puthash "/tmp/proj/" buf claude-emacs--sessions)
      (should (eq (claude-emacs--session-buffer "/tmp/proj/") buf))
      (kill-buffer buf)
      (should (null (claude-emacs--session-buffer "/tmp/proj/")))
      (should (null (gethash "/tmp/proj/" claude-emacs--sessions))))))

(ert-deftest claude-emacs-test-session-buffer-missing-root ()
  (claude-emacs-test--with-clean-sessions
    (should (null (claude-emacs--session-buffer "/nowhere/")))))

(ert-deftest claude-emacs-test-kill-session-removes-entry ()
  (claude-emacs-test--with-clean-sessions
    (let ((buf (generate-new-buffer "fake-claude-session-2")))
      (puthash "/tmp/proj2/" buf claude-emacs--sessions)
      (claude-emacs--kill-session "/tmp/proj2/")
      (should (null (gethash "/tmp/proj2/" claude-emacs--sessions)))
      (should-not (buffer-live-p buf)))))

(ert-deftest claude-emacs-test-project-root-falls-back-to-default-directory ()
  (let ((default-directory (expand-file-name temporary-file-directory)))
    (cl-letf (((symbol-function 'project-current) (lambda (&optional _) nil)))
      (should (equal (claude-emacs--project-root)
                      (expand-file-name temporary-file-directory))))))

(ert-deftest claude-emacs-test-ensure-vterm-errors-without-package ()
  (let ((orig-require (symbol-function 'require)))
    (cl-letf (((symbol-function 'require)
               (lambda (feature &optional filename noerror)
                 (if (eq feature 'vterm)
                     nil
                   (funcall orig-require feature filename noerror)))))
      (should-error (claude-emacs--ensure-vterm) :type 'user-error))))

(provide 'claude-emacs-test)
;;; claude-emacs-test.el ends here
