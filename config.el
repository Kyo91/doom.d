;;; $DOOMDIR/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here! Remember, you do not need to run 'doom
;; sync' after modifying this file!


;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "Samuel Blumenthal"
      user-mail-address "sblumenthal@medallia.com")

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
(setq display-line-numbers-type t)


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


(setq python-python-command "/Users/sblumenthal/.pyenv/shims/python")


(setq org-agenda-files '("~/agenda/")
      org-refile-use-outline-path 'file
      org-outline-path-complete-in-steps nil)

;; (use-package! lsp-python-ms
;;   :init (setq lsp-python-ms-executable
;;               "~/python-language-server/output/bin/Release/osx-x64/publish/Microsoft.Python.LanguageServer")
;;   :hook (python-mode . (lambda ()
;;                          (require 'lsp-python-ms)
;;                          (lsp))))

; Fix airflow dags path
;; (add-to-list 'lsp-python-ms-extra-paths "/Users/sblumenthal/workplace/athena-scheduler/dags/")

(add-hook 'python-mode-hook #'(lambda () (electric-indent-mode -1)))

(remove-hook 'org-mode-hook #'auto-fill-mode)
(remove-hook 'markdown-mode-hook #'auto-fill-mode)
(remove-hook 'text-mode-hook #'auto-fill-mode)

(setq max-specpdl-size 13000)
(setq conda-anaconda-home "$HOME/miniconda3/")

; Set conda envs are venv home
(setenv "WORKON_HOME" "/Users/sblumenthal/miniconda3/envs")
(pyvenv-mode 1)

; Fix company-lsp result order
(add-hook 'python-mode-hook (lambda () (setq company-lsp-cache-candidates nil)))

(setq display-line-numbers-type 'relative)

(use-package! lsp-mode
  :init
  (setq lsp-pyls-plugins-pylint-enabled t)
  (setq lsp-pyls-plugins-autopep8-enabled nil)
  (setq lsp-pyls-plugins-yapf-enabled t)
  (setq lsp-pyls-plugins-pyflakes-enabled nil)
)

(setq doom-localleader-key ",")

(add-to-list '+format-on-save-enabled-modes 'web-mode t)
