;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "Samuel Blumenthal"
      user-mail-address "sam.sam.42@gmail.com")

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
(setq doom-font (font-spec :family "monospace" :size 14))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-one)

;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-directory "~/agenda/")

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
      :gi "C-b" #'backward-char

      :leader
      :desc "Calc" "a c" #'calc)



(setq org-agenda-files '("~/agenda/")
      org-refile-use-outline-path 'file
      org-outline-path-complete-in-steps nil)


; Fix airflow dags path

(add-hook 'python-mode-hook #'(lambda () (electric-indent-mode -1)))

(remove-hook 'org-mode-hook #'auto-fill-mode)
(remove-hook 'markdown-mode-hook #'auto-fill-mode)
(remove-hook 'text-mode-hook #'auto-fill-mode)

(setq max-specpdl-size 13000)
(setq conda-anaconda-home "$HOME/miniconda3/")

; Fix company-lsp result order
(add-hook 'python-mode-hook (lambda () (setq company-lsp-cache-candidates nil)))

(setq display-line-numbers-type 'relative)


(setq doom-localleader-key ",")

(add-to-list '+format-on-save-enabled-modes 'web-mode t)
(setenv "PATH" (concat "/home/sam/.local/bin/:/home/sam/.poetry/bin/:" (getenv "PATH")))
(add-to-list 'exec-path "/home/sam/.local/bin/")
(add-to-list 'exec-path "/home/sam/.poetry/bin/")


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

;; (use-package! fira-code-mode
;;   :hook prog-mode)

(use-package! blacken
  :init
  (setq blacken-executable "~/.local/bin/black"))

(add-hook 'clojure-mode-hook (lambda () (lispy-mode -1)))
(add-hook 'clojure-mode-hook (lambda () (paredit-mode 1)))


;; ;; Elixir LSP over tramp
;; (lsp-register-client
;;  (make-lsp-client :new-connection (lsp-tramp-connection
;;                                    (lambda ()
;;                                      `(,(or (executable-find
;;                                             (cl-first lsp-elixir-server-command))
;;                                            (lsp-package-path 'elixir-ls))
;;                                        ,@(cl-rest lsp-elixir-server-command))))
;;                   :major-modes '(elixir-mode)
;;                   :priority -1
;;                   :server-id 'elixir-ls
;;                   :remote? t
;;                   :action-handlers (ht ("elixir.lens.test.run" 'lsp-elixir--run-test))
;;                   :initialized-fn (lambda (workspace)
;;                                     (with-lsp-workspace workspace
;;                                       (lsp--set-configuration
;;                                        (lsp-configuration-section "elixirLS")))
;;                                     (puthash
;;                                      "textDocumentSync"
;;                                      (ht ("save" t)
;;                                          ("change" 2))
;;                                      (lsp--workspace-server-capabilities workspace)))))

(use-package! protobuf-mode)

(plist-put! +ligatures-extra-symbols
            :true nil
            :false nil
            :str nil
            :bool nil
            :list nil)

;; 10min cache expiry on remote projects (default 5min)
(setq projectile-file-exists-remote-cache-expire (* 10 60))

(setq mac-command-modifier 'super)
