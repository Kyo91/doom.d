;;; misc.el -*- lexical-binding: t; -*-

;; Miscelanous elisp code, functions, etc
(defun kyo/default-project-agenda-text (project-name)
  (concat "#+TITLE: " project-name "\n* " (capitalize project-name) " Items"))

(defun kyo//open-project-agenda (project-name &optional insert-todo)
  (let* ((file-name (concat "project-" project-name ".org"))
         (path (doom-path org-directory file-name))
         (text (kyo/default-project-agenda-text project-name)))
    (if (file-exists-p path)
        (progn
          (find-file path))
      (progn
        (find-file path)
        (insert text)))
    (when insert-todo
        (org-insert-todo-heading nil))))

(defun kyo/open-project-agenda ()
  (interactive)
  (kyo//open-project-agenda (projectile-project-name) (yes-or-no-p "Create todo?")))
