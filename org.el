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
                 ;; Keep deadline-only TODOs here until they come within
                 ;; `org-deadline-warning-days' (then they show in the agenda
                 ;; block above); still hide scheduled and plain-timestamped ones.
                 (org-agenda-todo-ignore-deadlines 'near)
                 (org-agenda-todo-ignore-timestamp 'all)
                 (org-agenda-todo-ignore-with-date nil)))))
        ("h" "Home focus (exclude WORK)"
         ((agenda ""
                  ((org-agenda-span 1)))
          (tags-todo ,(concat "-" my/org-question-tag "/-WAIT")
                     ((org-agenda-overriding-header "Unscheduled TODOs")
                      (org-agenda-tags-todo-honor-ignore-options t)
                      (org-agenda-todo-ignore-scheduled 'all)
                      ;; Keep deadline-only TODOs here until they come within
                      ;; `org-deadline-warning-days' (then they show in the agenda
                      ;; block above); still hide scheduled and plain-timestamped ones.
                      (org-agenda-todo-ignore-deadlines 'near)
                      (org-agenda-todo-ignore-timestamp 'all)
                      (org-agenda-todo-ignore-with-date nil)))
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
                      ;; Keep deadline-only TODOs here until they come within
                      ;; `org-deadline-warning-days' (then they show in the agenda
                      ;; block above); still hide scheduled and plain-timestamped ones.
                      (org-agenda-todo-ignore-deadlines 'near)
                      (org-agenda-todo-ignore-timestamp 'all)
                      (org-agenda-todo-ignore-with-date nil)))
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

;; Vulpea (replaces org-roam)
;;
;; Notes still live in ~/agenda/roam/ and keep the org-roam on-disk format
;; (ID property drawers, #+title, #+filetags, id: links), so switching back
;; only means re-enabling `+roam'.  These must be set before vulpea loads:
;; vulpea derives several defaults at load time.
(defvar my/notes-directory (expand-file-name "~/agenda/roam/")
  "Root of the vulpea note collection.")

(setq vulpea-db-sync-directories (list my/notes-directory)
      vulpea-default-notes-directory my/notes-directory
      vulpea-db-location (file-name-concat doom-profile-data-dir "vulpea.db")
      ;; Existing notes use org-roam's alias property.
      vulpea-buffer-alias-property "ROAM_ALIASES"
      ;; Same file naming as the old org-roam templates.
      vulpea-create-default-template '(:file-name "${timestamp}-${slug}.org")
      vulpea-db-sync-verbose nil)

(defvar my/vulpea-templates
  '((?d "default" :file-name "${timestamp}-${slug}.org")
    (?w "work" :file-name "work/${timestamp}-${slug}.org" :tags ("WORK"))
    (?q "quote" :file-name "work/${timestamp}-${slug}.org" :tags ("WORK")
        :body "#+begin_quote\n%?\n#+end_quote")
    (?p "placeholder" :file-name "${timestamp}-${slug}.org"
        :body "Placeholder for ${title}" :visit nil))
  "Note templates, ported from the old `org-roam-capture-templates'.
Each entry is (KEY NAME . PLIST).  PLIST takes `vulpea-create's :file-name,
:tags and :body, plus :visit (default t).  A \"%?\" in :body marks where
point lands after the note is visited.")

(defun my/vulpea--read-template ()
  "Prompt for one of `my/vulpea-templates' and return it."
  (if (cdr my/vulpea-templates)
      (assq (car (read-multiple-choice
                  "Template" (mapcar (lambda (tpl) (list (car tpl) (cadr tpl)))
                                     my/vulpea-templates)))
            my/vulpea-templates)
    (car my/vulpea-templates)))

(defun my/vulpea--create-from-template (title template)
  "Create a note titled TITLE from TEMPLATE without visiting it."
  (let ((plist (cddr template)))
    (vulpea-create title (plist-get plist :file-name)
                   :tags (plist-get plist :tags)
                   :body (plist-get plist :body))))

(defun my/vulpea--visit-new (note template)
  "Visit freshly created NOTE, moving point to TEMPLATE's %? marker."
  (find-file (vulpea-note-path note))
  (goto-char (point-min))
  (if (search-forward "%?" nil t)
      (replace-match "")
    (goto-char (point-max)))
  (when (and (bound-and-true-p evil-local-mode)
             (string-match-p "%\\?" (or (plist-get (cddr template) :body) "")))
    (evil-insert-state)))

(defun my/vulpea-create (&optional title template)
  "Create a note titled TITLE from TEMPLATE, like `org-roam-capture'."
  (interactive)
  (require 'vulpea)
  (let* ((title (or title (read-string "Title: ")))
         (template (or template (my/vulpea--read-template)))
         (note (my/vulpea--create-from-template title template)))
    (when (plist-get (append (cddr template) '(:visit t)) :visit)
      (my/vulpea--visit-new note template))
    note))

(defun my/vulpea-find-create (title &optional _props)
  "Create TITLE via a template from `vulpea-find'.
Returns nil because the note was already visited."
  (my/vulpea-create title)
  nil)

(defun my/vulpea-insert-create (title &optional _props)
  "Create TITLE via a template from `vulpea-insert' without leaving the buffer."
  (let ((template (copy-tree (my/vulpea--read-template))))
    ;; The note is never visited here, so drop the point marker.
    (when-let ((body (plist-get (cddr template) :body)))
      (setcdr (cdr template)
              (plist-put (cddr template) :body (string-replace "%?" "" body))))
    (my/vulpea--create-from-template title template)))

(defun my/vulpea-find-ref ()
  "Find a note by its ROAM_REFS, like `org-roam-ref-find'."
  (interactive)
  (require 'vulpea)
  (let (candidates)
    (dolist (note (vulpea-db-query-by-property-key "ROAM_REFS"))
      (dolist (ref (split-string-and-unquote
                    (or (cdr (assoc "ROAM_REFS" (vulpea-note-properties note))) "")))
        (push (cons (format "%s  %s" ref
                            (propertize (vulpea-note-title note) 'face 'shadow))
                    note)
              candidates)))
    (unless candidates (user-error "No notes with ROAM_REFS"))
    (vulpea-visit (cdr (assoc (completing-read "Ref: " candidates nil t)
                              candidates)))))

(defun my/vulpea-find-forward-link ()
  "Select and visit a note linked from the current note."
  (interactive)
  (require 'vulpea)
  (let* ((id (or (org-entry-get nil "ID" t)
                 (user-error "Current location has no ID property")))
         (ids (delete-dups
               (seq-keep (lambda (link)
                           (when (equal (plist-get link :type) "id")
                             (plist-get link :dest)))
                         (vulpea-db-query-links-from id))))
         (notes (or (vulpea-db-query-by-ids ids)
                    (user-error "No forward links"))))
    (vulpea-visit (vulpea-select-from "Forward link" notes :require-match t))))

(defun my/vulpea-random ()
  "Visit a random file-level note, like `org-roam-node-random'."
  (interactive)
  (require 'vulpea)
  (vulpea-visit (seq-random-elt (or (vulpea-db-query-by-level 0)
                                    (user-error "No notes indexed yet")))))

(defun my/vulpea-refile ()
  "Refile the current subtree into a note, like `org-roam-refile'."
  (interactive)
  (require 'vulpea)
  (let* ((note (vulpea-select "Refile to" :require-match t))
         (pos (unless (zerop (vulpea-note-level note))
                (cdr (org-id-find (vulpea-note-id note))))))
    (org-refile nil nil (list (vulpea-note-title note)
                              (vulpea-note-path note) nil pos))))

(defun my/vulpea-note-buffer-h ()
  "Set up buffers visiting files in `my/notes-directory'."
  (when (and buffer-file-name
             (not (bound-and-true-p vulpea-db--active-parse-method))
             (file-in-directory-p buffer-file-name my/notes-directory))
    ;; Same as Doom's +roam: links stored from notes use IDs.
    (setq-local org-id-link-to-org-use-id 'create-if-interactive)
    (vulpea-title-change-detection-mode +1)))

(add-hook 'org-mode-hook #'my/vulpea-note-buffer-h)

;; Bound below but not autoloaded upstream.
(dolist (cmd '(vulpea-buffer-alias-add vulpea-buffer-alias-remove
               vulpea-buffer-tags-add vulpea-buffer-tags-remove))
  (autoload cmd "vulpea-buffer" nil t))
(autoload 'vulpea-tags-batch-rename "vulpea-tags" nil t)

(use-package! vulpea
  :defer t
  ;; Start the database/watchers on first input instead of blocking startup.
  :after-call doom-first-input-hook
  :init
  (setq vulpea-find-default-create-fn #'my/vulpea-find-create
        vulpea-insert-default-note-fn #'my/vulpea-insert-create)
  :config
  (defadvice! my/vulpea-insert-after-point-a (fn &rest args)
    "In evil normal state, insert the link after point, like Doom's roam advice."
    :around #'vulpea-insert
    (if (and (bound-and-true-p evil-local-mode)
             (not (evil-insert-state-p))
             (or (looking-at-p "[[:blank:]]") (evil-eolp)))
        (evil-with-state 'insert
          (unless (eolp) (forward-char))
          (when (evil-eolp) (insert " "))
          (apply fn args))
      (apply fn args)))
  (vulpea-db-autosync-mode +1))

(use-package! consult-vulpea
  ;; Must not be `:after consult' (see consult-vulpea README).
  :after vulpea
  :config
  (consult-vulpea-mode 1)
  (map! :map minibuffer-local-map
        "C-<right>" #'consult-vulpea-go-to-next-backlink-overlay
        "C-<left>"  #'consult-vulpea-go-to-previous-backlink-overlay))

(use-package! vulpea-ui
  :defer t
  :config
  (setq vulpea-ui-sidebar-position 'right
        vulpea-ui-sidebar-size 0.33))

(map! :leader
      (:prefix ("n r" . "notes (vulpea)")
       :desc "Open random note"       "a" #'my/vulpea-random
       :desc "Find backlink"          "b" #'vulpea-find-backlink
       :desc "Doctor"                 "d" #'vulpea-doctor
       :desc "Find note"              "f" #'vulpea-find
       :desc "Find ref"               "F" #'my/vulpea-find-ref
       :desc "Insert link"            "i" #'vulpea-insert
       :desc "Find forward link"      "l" #'my/vulpea-find-forward-link
       :desc "Move note file"         "m" #'vulpea-move-file
       :desc "New note"               "n" #'my/vulpea-create
       :desc "Propagate title change" "p" #'vulpea-propagate-title-change
       :desc "Toggle sidebar"         "r" #'vulpea-ui-sidebar-toggle
       :desc "Rename tag everywhere"  "R" #'vulpea-tags-batch-rename
       :desc "Sync database"          "s" #'vulpea-db-sync-full-scan
       :desc "Search notes"           "/" #'consult-vulpea-grep))

(map! :map org-mode-map
      :localleader
      (:prefix ("m" . "notes (vulpea)")
       :desc "Add alias"              "a" #'vulpea-buffer-alias-add
       :desc "Remove alias"           "A" #'vulpea-buffer-alias-remove
       :desc "Find backlink"          "b" #'vulpea-find-backlink
       :desc "Find note"              "f" #'vulpea-find
       :desc "Find ref"               "F" #'my/vulpea-find-ref
       :desc "Insert link"            "i" #'vulpea-insert
       :desc "Create ID"              "I" #'org-id-get-create
       :desc "Find forward link"      "l" #'my/vulpea-find-forward-link
       :desc "Toggle sidebar"         "m" #'vulpea-ui-sidebar-toggle
       :desc "New note"               "n" #'my/vulpea-create
       :desc "Refile to note"         "r" #'my/vulpea-refile
       :desc "Search notes"           "s" #'consult-vulpea-grep
       :desc "Add tag"                "t" #'vulpea-buffer-tags-add
       :desc "Remove tag"             "T" #'vulpea-buffer-tags-remove
       :desc "Split heading to note"  "x" #'vulpea-split-heading))

(setq deft-directory "~/agenda/"
      deft-recursive t)

(use-package! agent-shell-org-transcript
  :after agent-shell
  :config
  (setq agent-shell-org-transcript-directory
        (expand-file-name "work/" my/notes-directory)))

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
