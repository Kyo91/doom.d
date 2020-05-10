;;; ~/.doom.d/config.el -*- lexical-binding: t; -*-

;; Place your private configuration here

(map! :map org-mode-map

      [remap +org/insert-item-below] #'org-insert-heading-respect-content
      )

(map! :gi "C-f" #'forward-char
      :gi "C-b" #'backward-char

      :leader
      :desc "Calc" "a c" #'calc)


(setq python-python-command "/Users/sblumenthal/.pyenv/shims/python")

(use-package! exec-path-from-shell)

(setq org-agenda-files '("~/agenda/")
      org-refile-use-outline-path 'file
      org-outline-path-complete-in-steps nil)

(when (memq window-system '(mac ns x))
  (exec-path-from-shell-initialize))

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

(setq org-agenda-files '("~/agenda")
      org-directory "~/agenda/")

 (setq max-specpdl-size 13000)

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
