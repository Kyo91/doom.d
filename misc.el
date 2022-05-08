;;; misc.el -*- lexical-binding: t; -*-

;; Miscelanous elisp code, functions, etc
(defun kyo/default-project-agenda-text (project-name)
  (concat "#+TITLE: " project-name "\n* " (capitalize project-name) " Items"))

(defun kyo//open-project-agenda (project-name)
  (let* ((file-name (concat "project-" project-name ".org"))
         (path (doom-path org-directory file-name))
         (text (kyo/default-project-agenda-text project-name)))
    (if (file-exists-p path)
        (progn
          (find-file path)
          (org-insert-todo-heading nil))
      (progn
        (find-file path)
        (insert text)))))

(defun kyo/open-project-agenda () (interactive)
  (kyo//open-project-agenda (projectile-project-name)))
