;;; org.el -*- lexical-binding: t; -*-

;; Org
(setq org-directory "~/agenda/")

(map! :map org-mode-map
      [remap +org/insert-item-below] #'org-insert-heading-respect-content)

;; Questions for colleagues: TODO headlines tagged QUESTION (directly or via
;; inheritance) plus a tag naming the person to ask, e.g. JKURTZ.
(defvar my/org-question-tag "QUESTION"
  "Tag marking a TODO headline as an open question.")

(defvar my/org-question-ignored-tags '("QUESTION" "WORK")
  "Tags that never identify the person a question is for.")

(defun my/org-question-people ()
  "Return the sorted person tags used on open questions in agenda files."
  (let (people)
    (org-map-entries
     (lambda ()
       (dolist (tag (org-get-tags))
         (let ((tag (substring-no-properties tag)))
           (unless (or (member tag my/org-question-ignored-tags)
                       (member tag people))
             (push tag people)))))
     (concat "+" my/org-question-tag "/!-WAIT")
     'agenda)
    (sort people #'string<)))

(defun my/org-agenda-questions (&optional _match)
  "Show open questions as a block agenda with one block per person tag.
Questions without a person tag are listed after those, and questions
in WAIT state (asked, awaiting an answer) follow.  Answered (DONE)
questions are listed at the very end for reference."
  (let* ((people (my/org-question-people))
         (settings '((org-agenda-hide-tags-regexp
                      (concat "\\`" (regexp-opt my/org-question-ignored-tags) "\\'"))))
         (blocks
          (append
           (mapcar (lambda (person)
                     `(tags-todo ,(concat "+" my/org-question-tag "+" person "/-WAIT")
                                 ((org-agenda-overriding-header
                                   ,(format "Questions for %s" person)))))
                   people)
           `((tags-todo ,(concat "+" my/org-question-tag
                                 (mapconcat (lambda (p) (concat "-" p)) people "")
                                 "/-WAIT")
                        ((org-agenda-overriding-header "Questions (no person tag)")))
             (tags-todo ,(concat "+" my/org-question-tag "/WAIT")
                        ((org-agenda-overriding-header "Pending Questions")))
             (tags ,(concat "+" my/org-question-tag "/DONE")
                   ((org-agenda-overriding-header "Answered Questions")))))))
    (org-agenda-run-series "Open questions" (list blocks settings))
    ;; Recompute the person blocks on `g' instead of replaying the old series,
    ;; so newly added people show up after a refresh.
    (when (buffer-live-p org-agenda-buffer)
      (with-current-buffer org-agenda-buffer
        (let ((inhibit-read-only t))
          (add-text-properties (point-min) (point-max)
                               '(org-series-redo-cmd (my/org-agenda-questions))))
        (setq org-agenda-redo-command '(my/org-agenda-questions))))))

(setq org-agenda-files '("gtd.org" "todo.org" "ideas.org" "questions.org")
      org-refile-use-outline-path 'file
      org-outline-path-complete-in-steps nil
      org-agenda-custom-commands
      `(("g" "Daily reminders"
         ((agenda ""
                  ((org-agenda-span 1)))
          (todo ""
                ((org-agenda-overriding-header "Unscheduled TODOs")
                 (org-agenda-todo-ignore-scheduled 'all)
                 (org-agenda-todo-ignore-deadlines 'all)
                 (org-agenda-todo-ignore-with-date 'all)))))
        ("h" "Home focus (exclude WORK)"
         ((agenda ""
                  ((org-agenda-span 1)))
          (tags-todo ,(concat "-" my/org-question-tag "/-WAIT")
                     ((org-agenda-overriding-header "Unscheduled TODOs")
                      (org-agenda-tags-todo-honor-ignore-options t)
                      (org-agenda-todo-ignore-scheduled 'all)
                      (org-agenda-todo-ignore-deadlines 'all)
                      (org-agenda-todo-ignore-with-date 'all)))
          (todo "WAIT"
                ((org-agenda-overriding-header "Currently Blocked")))
          (tags-todo ,(concat "+" my/org-question-tag "/-WAIT")
                     ((org-agenda-overriding-header "Questions"))))
         ((org-agenda-tag-filter-preset '("-WORK"))
          (org-agenda-skip-function
           '(org-agenda-skip-entry-if 'todo '("PROJ")))))
        ("w" "Work focus (WORK only)"
         ((agenda ""
                  ((org-agenda-span 1)))
          (tags-todo ,(concat "-" my/org-question-tag "/-WAIT")
                     ((org-agenda-overriding-header "Unscheduled TODOs")
                      (org-agenda-tags-todo-honor-ignore-options t)
                      (org-agenda-todo-ignore-scheduled 'all)
                      (org-agenda-todo-ignore-deadlines 'all)
                      (org-agenda-todo-ignore-with-date 'all)))
          (todo "WAIT"
                ((org-agenda-overriding-header "Currently Blocked")))
          (tags-todo ,(concat "+" my/org-question-tag "/-WAIT")
                     ((org-agenda-overriding-header "Questions"))))
         ((org-agenda-tag-filter-preset '("+WORK"))
          (org-agenda-skip-function
           '(org-agenda-skip-entry-if 'todo '("PROJ")))))
        ("Q" "Open questions (by person)" my/org-agenda-questions)))

(remove-hook 'org-mode-hook #'auto-fill-mode)

(after! org
  (setq org-log-done 'time
        org-todo-keywords '((sequence "TODO(t)" "PROJ(p)" "LOOP(l)" "STRT(s)"
                             "WAIT(w)" "HOLD(h)" "DELE(D)" "IDEA(i)"
                             "|" "DONE(d)" "KILL(k)" "REASSIGNED(r)")
                            (sequence "[ ](T)" "[-](S)" "[?](W)" "|" "[X](D)")
                            (sequence "|" "OKAY(o)" "YES(y)" "NO(n)"))
        my/org-capture-ideas-file (expand-file-name "ideas.org" org-directory)
        my/org-capture-questions-file (expand-file-name "questions.org" org-directory)
        org-capture-templates '(("t" "Personal todo" entry (file+headline +org-capture-todo-file "Inbox")
                                 "* TODO %?\n:PROPERTIES:\n:CREATED:  %U\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("T" "Todo (no context)" entry (file+headline +org-capture-todo-file "Inbox") "* TODO %?\n %i \nCreated at: %T" :prepend t)
                                ("d" "Daily todo" entry (file+headline +org-capture-todo-file "Dailies") "* TODO %? :WORK:\n:PROPERTIES:\n:CREATED:  %U\n:END:\n%i" :prepend nil)
                                ("w" "Work todo" entry (file+headline +org-capture-todo-file "Inbox") "* TODO %? :WORK:\n:PROPERTIES:\n:CREATED:  %U\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("Q" "Question" entry (file+headline my/org-capture-questions-file "Work Questions")
                                 "* TODO %? %^g\n:PROPERTIES:\n:CREATED:  %U\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("r" "Random Thoughts" entry (file+headline my/org-capture-ideas-file "Random")
                                 "* TODO %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("n" "Personal notes" entry (file+headline +org-capture-notes-file "Inbox")
                                 "* %u %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("j" "Journal" entry (file+olp+datetree +org-capture-journal-file)
                                 "* %U %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("p" "Templates for projects")
                                ("pt" "Project-local todo" entry
                                 (file+headline +org-capture-project-todo-file "Inbox") "* TODO %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i"
                                 :prepend t)
                                ("pn" "Project-local notes" entry
                                 (file+headline +org-capture-project-notes-file "Inbox") "* %U %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i"
                                 :prepend t)
                                ("pc" "Project-local changelog" entry
                                 (file+headline +org-capture-project-changelog-file "Unreleased")
                                 "* %U %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("o" "Centralized templates for projects")
                                ("ot" "Project todo" entry #'+org-capture-central-project-todo-file
                                 "* TODO %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i" :heading "Tasks" :prepend nil)
                                ("on" "Project notes" entry #'+org-capture-central-project-notes-file
                                 "* %U %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i" :heading "Notes" :prepend t)
                                ("oc" "Project changelog" entry #'+org-capture-central-project-changelog-file
                                 "* %U %?\n:PROPERTIES:\n:SOURCE:   %a\n:END:\n%i" :heading "Changelog" :prepend t))))

;; Org Modern's third-level fold markers (⯈ and ⯆) are not present in Fira
;; Code, so macOS renders them with a mismatched fallback font.
(after! org-modern
  (setq org-modern-fold-stars '(("▶" . "▼"))))

;; Org-roam
(setq org-roam-directory "~/agenda/roam/"
      org-roam-capture-templates '(("d" "default" plain "%?"
                                    :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                                                       "#+title: ${title}\n")
                                    :unnarrowed t)
                                   ("w" "work" plain "%?"
                                    :target (file+head "work/%<%Y%m%d%H%M%S>-${slug}.org"
                                                       "#+title: ${title}\n#+filetags: :WORK:\n")
                                    :unnarrowed t)
                                   ("q" "quote" plain "#+begin_quote\n%?\n#+end_quote"
                                    :target (file+head "work/%<%Y%m%d%H%M%S>-${slug}.org"
                                                       "#+title: ${title}\n")
                                    :unnarrowed t)
                                   ("p" "placeholder" plain "Placeholder for ${title}"
                                    :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                                                       "#+title: ${title}\n")
                                    :immediate-finish t)))

(after! org-roam
  (setq org-roam-list-files-commands '(find fd fdfind rg)))

(use-package! consult-org-roam
  :after org-roam
  :init
  (consult-org-roam-mode 1)
  :custom
  (consult-org-roam-grep-func #'consult-ripgrep)
  :config
  (map! :map org-mode-map
        :localleader
        :prefix ("m" . "org-roam")
        :desc "Find node with Consult" "f" #'consult-org-roam-file-find
        :desc "Show backlinks" "b" #'consult-org-roam-backlinks
        :desc "Show forward links" "l" #'consult-org-roam-forward-links
        :desc "Search Org-roam" "s" #'consult-org-roam-search))

;; (use-package! websocket
;;   :after org-roam)

;; (use-package! org-roam-ui
;;   :after org-roam
;;   :hook (after-init . org-roam-ui-mode)
;;   :config
;;   (setq org-roam-ui-sync-theme t
;;         org-roam-ui-follow t
;;         org-roam-ui-update-on-save t
;;         org-roam-ui-open-on-start t))

(setq deft-directory "~/agenda/"
      deft-recursive t)

(use-package! agent-shell-org-transcript
  :after agent-shell
  :config
  (setq agent-shell-org-transcript-directory
        (expand-file-name "work/" org-roam-directory)))

(defun my/org-goto-last-daily-headline ()
  "Move point to the last headline in the `Dailies' subtree."
  (org-with-wide-buffer
   (goto-char (point-min))
   (when (org-find-exact-headline-in-buffer "Dailies")
     (let ((last-headline (point))
           (subtree-end (save-excursion (org-end-of-subtree t t))))
       (while (re-search-forward org-heading-regexp subtree-end t)
         (setq last-headline (match-beginning 0)))
       (goto-char last-headline)))))

(defun my/toggle-org-todo-buffer ()
  "Toggle the agenda todo file, visiting its latest daily on first open."
  (interactive)
  (let* ((todo-file (+org-capture-todo-file))
         (buffer (get-file-buffer todo-file))
         (window (and buffer (get-buffer-window buffer))))
    (if window
        (delete-window window)
      (let ((new-buffer-p (not buffer))
            (buffer (find-file-noselect todo-file)))
        (pop-to-buffer buffer)
        (when new-buffer-p
          (my/org-goto-last-daily-headline))))))

(defun my/org-todo-buffer-p (buffer-or-name &rest _)
  "Return non-nil when BUFFER-OR-NAME visits the agenda todo file."
  (let ((buffer (if (bufferp buffer-or-name)
                    buffer-or-name
                  (get-buffer buffer-or-name))))
    (and buffer
         (equal (buffer-file-name buffer) (+org-capture-todo-file)))))

(set-popup-rule! #'my/org-todo-buffer-p
  :side 'bottom :height 0.35 :select t :modeline t :quit nil :ttl nil)

(defun my/org-find-file ()
  "Find a non-archive file in the Org agenda directory."
  (interactive)
  (require 'consult)
  (let ((default-directory (file-name-as-directory
                            (expand-file-name org-directory)))
        (consult-find-args
         (if (stringp consult-find-args)
             (concat consult-find-args " -not -name *_archive")
           (append consult-find-args '("-not" "-name" "*_archive")))))
    (call-interactively #'consult-find)))

(after! consult
  (consult-customize my/org-find-file
                     :preview-key 'any
                     :state (consult--file-preview)))

(map! :leader :desc "Find Org File" "o a f" #'my/org-find-file
      :leader :desc "Toggle todo buffer" "o t" #'my/toggle-org-todo-buffer)

(defun my/push-notes-update (&optional message)
  "Commit all changes in `org-directory' with MESSAGE, then pull and push.

When MESSAGE is empty, use a timestamped \"Agenda Update\" message.
If pulling or pushing fails, open the repository's Magit status buffer so the
failure can be resolved there."
  (interactive)
  (require 'magit)
  (let ((default-directory (file-name-as-directory
                            (expand-file-name org-directory)))
        (default-message (format-time-string
                          "Agenda Update %Y-%m-%d %H:%M:%S"))
        (previous-window-configuration (current-window-configuration)))
    (unless message
      (magit-status-setup-buffer default-directory)
      (magit-refresh)
      (condition-case err
          (setq message (read-string "Commit message: " nil nil
                                     default-message))
        (quit
         (set-window-configuration previous-window-configuration)
         (signal (car err) (cdr err)))))
    (when (string-empty-p (string-trim message))
      (setq message default-message))
    (unless (zerop (magit-call-git "add" "--all"))
      (user-error "Could not stage notes; see the Magit process buffer"))
    (unless (zerop (magit-call-git "commit" "-m" message))
      (user-error "Could not commit notes; see the Magit process buffer"))
    (dolist (operation '("pull" "push"))
      (unless (zerop (magit-call-git operation))
        (magit-status-setup-buffer default-directory)
        (user-error "Git %s failed; opened Magit status" operation)))
    (set-window-configuration previous-window-configuration)
    (message "Notes updated and pushed")))
