;;; +bindings.el -*- lexical-binding: t; -*-

(map! :leader
      :desc "Lang/Input Select" :nv "l" #'set-input-method
      :desc "Shell Command" :n "!" #'shell-command
      :desc "Jump" :nv "j" #'avy-goto-char-timer
      :desc "(Rip)grep" :n "pg" #'counsel-rg
      :desc "Project Agenda" :nv "pa" #'kyo/open-project-agenda
      (:desc "elisp" :prefix "e"
        :desc "defun" :n "f" #'eval-defun)
      (:desc "apps" :prefix "a"
        :desc "Calc" :n "c" #'calc))

;; Emacs style forwards/backwards in insert mode
(map!
 :i "C-f" #'forward-char
 :i "C-b" #'backward-char
 :i "C-x C-s" #'save-buffer)
