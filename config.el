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
        user-mail-address "sam.sam.42@gmail.com"))
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

;; (use-package! fira-code-mode
;;   :hook prog-mode)
;;
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
  (add-to-list
   'org-capture-templates
   '("w" "Work todo" entry (file+headline +org-capture-todo-file "Inbox") "* TODO %?\n %i %a \nCreated at: %T" :prepend t)))

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

(use-package! websocket
    :after org-roam)

(use-package! org-roam-ui
    :after org-roam ;; or :after org
;;         normally we'd recommend hooking orui after org-roam, but since org-roam does not have
;;         a hookable mode anymore, you're advised to pick something yourself
;;         if you don't care about startup time, use
    :hook (after-init . org-roam-ui-mode)
    :config
    (setq org-roam-ui-sync-theme t
          org-roam-ui-follow t
          org-roam-ui-update-on-save t
          org-roam-ui-open-on-start t))

(on-env 'linux
     (pixel-scroll-precision-mode))
