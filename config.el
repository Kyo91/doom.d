;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!
(defvar emacs-env "EMACS_ENV" "Environment variable used by emacs to determine the current environment.")
(defun sym-str-eq (a b)
  (or
   (and (stringp a) (stringp b) (string= a b))
   (and (symbolp a) (symbolp b) (eql a b))
   (and (stringp a) (symbolp b) (string= a (symbol-name b)))
   (and (symbolp a) (stringp b) (string= (symbol-name a) b))))
(defun flex-member (elt list comparison)
  (when list
    (if (funcall comparison elt (car list))
        t
      (flex-member elt (cdr list) comparison))))

(defmacro on-env (env-or-env-list body)
  (declare (indent defun))
  (let* ((env (getenv emacs-env)))
    `(when (or (sym-str-eq ,env ,env-or-env-list)
               (and (listp ,env-or-env-list) (flex-member ,env ,env-or-env-list 'sym-str-eq)))
       ,body)))

;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(on-env 'linux
  (setq user-full-name "Samuel Blumenthal"
        user-mail-address "me@itsleg.day"))
(on-env 'osx
  (setq user-full-name "Samuel Blumenthal"
        user-mail-address "sblumenthal@drw.com"))

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
;; (font-spec :family "monospace" :size 14) ; Default
(on-env 'osx (setq doom-font (font-spec :family "Fira Code" :size 12)))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
;; (setq doom-theme 'doom-one)
(setq doom-theme 'doom-solarized-light)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/agenda/")
(setq hywiki-directory "~/hywiki/")


(defun open-ai-notes-dir ()
  "Open the AI notes directory in Dired in another window."
  (interactive)
  (dired-other-window (file-name-as-directory (expand-file-name "~/claude-notes"))))

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type 'relative)


;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c g k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c g d') to jump to their definition and see how
;; they are implemented.
(map! :map org-mode-map

      [remap +org/insert-item-below] #'org-insert-heading-respect-content
      )

(map! :gi "C-f" #'forward-char
      :gi "C-b" #'backward-char)



(setq org-agenda-files '("~/agenda/")
      org-refile-use-outline-path 'file
      org-outline-path-complete-in-steps nil)


                                        ; Fix airflow dags path

(add-hook 'python-mode-hook #'(lambda () (electric-indent-mode -1)))

(remove-hook 'org-mode-hook #'auto-fill-mode)
(remove-hook 'markdown-mode-hook #'auto-fill-mode)
(remove-hook 'text-mode-hook #'auto-fill-mode)

(setq conda-anaconda-home "$HOME/miniconda3/")

(setq display-line-numbers-type 'relative)


(setq doom-localleader-key ",")

(setenv "PATH" (concat "/home/sam/.local/bin/:/home/sam/.poetry/bin/:" (getenv "PATH")))
(add-to-list 'exec-path "/home/sam/.local/bin/")
(add-to-list 'exec-path "/home/sam/.poetry/bin/")


(load! "misc")
(load! "+bindings")

;; emacs/eshell
(after! eshell
  (set-eshell-alias!
   "f"   "find-file $1"
   "l"   "ls -lh"
   "d"   "dired $1"
   "gl"  "(call-interactively 'magit-log-current)"
   "gs"  "magit-status"
   "gc"  "magit-commit"
   "rg"  "rg --color=always $*"))

(on-env 'osx
  (plist-put! +ligatures-extra-symbols
              :true "⊤"
              :false "⊥"
              :str "Ꮥ"
              :bool "ℬ"
              :list "ℒ"))
(on-env 'osx
  (setq projectile-file-exists-remote-cache-expire (* 10 60)))

(after! org
  (setq org-log-done 'time
        hywiki-directory "~/hywiki/"
        my/org-capture-ideas-file (expand-file-name "ideas.org" org-directory)
        org-capture-templates '(("t" "Personal todo" entry (file+headline +org-capture-todo-file "Inbox")
                                 "* TODO %?\n%i\n%a \nCreated at: %T" :prepend t)
                                ("T" "Todo (no context)" entry (file+headline +org-capture-todo-file "Inbox") "* TODO %?\n %i \nCreated at: %T" :prepend t)
                                ("d" "Daily todo" entry (file+headline +org-capture-todo-file "Dailies")
                                 ("w" "Work todo" entry (file+headline +org-capture-todo-file "Inbox") "* TODO %?\n %i %a \nCreated at: %T" :prepend t)
                                 "* TODO %?\n%i\n" :prepend nil)
                                ("r" "Random Thoughts" entry (file+headline my/org-capture-ideas-file "Random")
                                 "* TODO %?\n%i\n%a" :prepend t)
                                ("n" "Personal notes" entry (file+headline +org-capture-notes-file "Inbox")
                                 "* %u %?\n%i\n%a" :prepend t)
                                ("j" "Journal" entry (file+olp+datetree +org-capture-journal-file)
                                 "* %U %?\n%i\n%a" :prepend t)
                                ("p" "Templates for projects")
                                ("pt" "Project-local todo" entry
                                 (file+headline +org-capture-project-todo-file "Inbox") "* TODO %?\n%i\n%a"
                                 :prepend t)
                                ("pn" "Project-local notes" entry
                                 (file+headline +org-capture-project-notes-file "Inbox") "* %U %?\n%i\n%a"
                                 :prepend t)
                                ("pc" "Project-local changelog" entry
                                 (file+headline +org-capture-project-changelog-file "Unreleased")
                                 "* %U %?\n%i\n%a" :prepend t)
                                ("o" "Centralized templates for projects")
                                ("ot" "Project todo" entry #'+org-capture-central-project-todo-file
                                 "* TODO %?\n %i\n %a" :heading "Tasks" :prepend nil)
                                ("on" "Project notes" entry #'+org-capture-central-project-notes-file
                                 "* %U %?\n %i\n %a" :heading "Notes" :prepend t)
                                ("oc" "Project changelog" entry #'+org-capture-central-project-changelog-file
                                 "* %U %?\n %i\n %a" :heading "Changelog" :prepend t)))
  )
(use-package! blacken
  :init
  (setq blacken-executable "~/.local/bin/black"))

(add-hook 'clojure-mode-hook (lambda () (lispy-mode -1)))
(add-hook 'clojure-mode-hook (lambda () (paredit-mode 1)))

;; Lisp settings
(on-env 'linux
  (setq
   sly-complete-symbol-function 'sly-flex-completions
   inferior-lisp-program "/usr/local/bin/ros -Q run"
   ))

(setq deft-directory "~/agenda/"
      deft-recursive t)

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

;; (use-package! websocket
;;   :after org-roam)

;; (use-package! org-roam-ui
;;   :after org-roam ;; or :after org
;;   ;;         normally we'd recommend hooking orui after org-roam, but since org-roam does not have
;;   ;;         a hookable mode anymore, you're advised to pick something yourself
;;   ;;         if you don't care about startup time, use
;;   :hook (after-init . org-roam-ui-mode)
;;   :config
;;   (setq org-roam-ui-sync-theme t
;;         org-roam-ui-follow t
;;         org-roam-ui-update-on-save t
;;         org-roam-ui-open-on-start t))

(pixel-scroll-precision-mode)

(after! scala-mode
  (setq scala-indent:use-javadoc-style nil))

(set-eglot-client! '(scala-mode scala-ts-mode)
                   '("metals"
                     "-J-Dmetals.startMcpServer=true"
                     "-J-Dmetals.mcpClient=claude"
                     :initializationOptions (:isHttpEnabled t)))

(setq
 projectile-project-root-functions '(projectile-root-local
                                     projectile-root-top-down
                                     projectile-root-top-down-recurring
                                     projectile-root-bottom-up))

(use-package! jsonnet-mode
  :defer t
  )

(defun shou/fix-apheleia-project-dir (orig-fn &rest args)
  (let ((project (project-current)))
    (if (not (null project))
        (let ((default-directory (project-root project))) (apply orig-fn args))
      (apply orig-fn args))))

(advice-add 'apheleia-format-buffer :around #'shou/fix-apheleia-project-dir)


(defun build-image (dev-build)
  (interactive "sDEV_BUILD=")
  (let* ((default-directory (project-root (project-current t)))
         (compilation-environment (list (concat "DEV_BUILD=" dev-build)))
         (build-command (format "~/bin/dev-image.sh %s" dev-build)))
    (message (car compilation-environment))
    (compile build-command)))

(setq compilation-scroll-output t)
(setq magit-list-refs-sortby "-creatordate")

(add-to-list '+format-on-save-disabled-modes 'python-mode)

(use-package! claude-code-ide
  :bind ("C-c C-'" . claude-code-ide-menu)
  :config (claude-code-ide-emacs-tools-setup)
  (setq claude-code-ide-vterm-render-delay 0.01)
  )

(use-package! acp)
(use-package! agent-shell
  :ensure-system-package
  ((claude . "brew install claude-code")
   (claude-agent-acp . "npm install -g @agentclientprotocol/claude-agent-acp"))
  :config
  (require 'acp)
  (require 'agent-shell)
  (setq agent-shell-anthropic-authentication (agent-shell-anthropic-make-authentication :login t))
  (map! :leader "b a" #'agent-shell-switch-buffer)
  (setq agent-shell-openai-authentication
        (agent-shell-openai-make-authentication :api-key "")))

(after! agent-shell
  (defcustom *my/agent-shell-reviewer-model* "gpt-5.6-sol"
    "Model used by `my/agent-shell-start-review'."
    :type 'string
    :group 'agent-shell)

  (defcustom *my/agent-shell-reviewer-effort-level* "high"
    "Reasoning effort used by `my/agent-shell-start-review'."
    :type 'string
    :group 'agent-shell)

  (defun my/agent-shell-start-review ()
    "Start a Codex code-review session and prepare an editable prompt."
    (interactive)
    (let* ((model *my/agent-shell-reviewer-model*)
           (effort-level *my/agent-shell-reviewer-effort-level*)
           (prompt (concat "Review the code changes on this branch. Focus on "
                           "readability, idiomatic Scala usage, and concise, "
                           "useful comments."))
           (config (agent-shell-openai-make-codex-config))
           (shell-buffer nil)
           (subscription nil))
      ;; Override the model for this review session without changing the
      ;; default used by other Codex sessions.
      (map-put! config :default-model-id (lambda () model))
      (setq shell-buffer
            (agent-shell--start :config config :new-session t :no-focus t))
      (setq subscription
            (agent-shell-subscribe-to
             :shell-buffer shell-buffer
             :event 'init-finished
             :on-event
             (lambda (_event)
               (agent-shell-unsubscribe :subscription subscription)
               (with-current-buffer shell-buffer
                 (agent-shell--config-option-set-thought-level-id
                  :thought-level-id effort-level
                  :on-success
                  (lambda ()
                    (agent-shell-insert :text prompt
                                        :shell-buffer shell-buffer)))))))
      (agent-shell--display-buffer shell-buffer))))

(use-package! agent-shell-sidebar
  :after agent-shell
  :custom
  (agent-shell-sidebar-width "25%")
  (agent-shell-sidebar-minimum-width 80)
  (agent-shell-sidebar-maximum-width "50%")
  (agent-shell-sidebar-position 'right)
  (agent-shell-sidebar-locked t)
  (agent-shell-sidebar-default-config
   (agent-shell-anthropic-make-claude-code-config))
  :bind
  (("C-c a s" . agent-shell-sidebar-toggle)
   ("C-c a f" . agent-shell-sidebar-toggle-focus)))
(use-package! agent-shell-org-transcript :after agent-shell)

(use-package! agent-shell-dispatch :after agent-shell
              :custom (agent-shell-dispatch-global-mode 1))

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

;; Helper for quickly finding org files
(defun my/org-find-file ()
  "Find a file in the Org agenda directory."
  (interactive)
  (let ((default-directory (file-name-as-directory
                            (expand-file-name org-directory))))
    (call-interactively #'consult-find)))

(map! :leader :desc "Find Org File" "o a f" #'my/org-find-file
      :leader :desc "Toggle todo buffer" "o t" #'my/toggle-org-todo-buffer)

;;; Hyperbole
(after! hyperbole
  ;; Enable Hyperbole globally.
  (hyperbole-mode 1)

  ;; enable hywiki-mode and make HyWikiWords appear everywhere
  (hywiki-mode :all)

  (setq hyrolo-file-list (list "~/.rolo.org" org-directory hywiki-directory)
        hsys-org-enable-smart-keys t))

(map! :leader
      :prefix ("H" . "hyperbole")
      :desc "Hyperbole menu" "h" #'hyperbole
      :desc "Action" "a" #'hkey-either
      :desc "Toggle Hyperbole mode" "m" #'hyperbole-mode)
