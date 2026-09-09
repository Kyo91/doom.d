;;; org.el -*- lexical-binding: t; -*-

;; Org
(setq org-directory "~/agenda/")

(map! :map org-mode-map
      [remap +org/insert-item-below] #'org-insert-heading-respect-content)

(setq org-agenda-files '("~/agenda/")
      org-refile-use-outline-path 'file
      org-outline-path-complete-in-steps nil)

(remove-hook 'org-mode-hook #'auto-fill-mode)

(after! org
  (setq org-log-done 'time
        my/org-capture-ideas-file (expand-file-name "ideas.org" org-directory)
        org-capture-templates '(("t" "Personal todo" entry (file+headline +org-capture-todo-file "Inbox")
                                 "* TODO %?\n:PROPERTIES:\n:CREATED:  %U\n:SOURCE:   %a\n:END:\n%i" :prepend t)
                                ("T" "Todo (no context)" entry (file+headline +org-capture-todo-file "Inbox") "* TODO %?\n %i \nCreated at: %T" :prepend t)
                                ("d" "Daily todo" entry (file+headline +org-capture-todo-file "Dailies") "* TODO %?\n:PROPERTIES:\n:CREATED:  %U\n:END:\n%i" :prepend nil)
                                ("w" "Work todo" entry (file+headline +org-capture-todo-file "Inbox") "* TODO %?\n:PROPERTIES:\n:CREATED:  %U\n:SOURCE:   %a\n:END:\n%i" :prepend t)
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

;; Org-roam
(setq org-roam-directory "~/agenda/roam/"
      org-roam-capture-templates '(("d" "default" plain "%?"
                                    :target (file+head "%<%Y%m%d%H%M%S>-${slug}.org"
                                                       "#+title: ${title}\n")
                                    :unnarrowed t)
                                   ("w" "work" plain "%?"
                                    :target (file+head "work/%<%Y%m%d%H%M%S>-${slug}.org"
                                                       "#+title: ${title}\n")
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
  "Find a file in the Org agenda directory."
  (interactive)
  (let ((default-directory (file-name-as-directory
                            (expand-file-name org-directory))))
    (call-interactively #'consult-find)))

(map! :leader :desc "Find Org File" "o a f" #'my/org-find-file
      :leader :desc "Toggle todo buffer" "o t" #'my/toggle-org-todo-buffer)
