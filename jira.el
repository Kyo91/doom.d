;;; jira.el -*- lexical-binding: t; -*-

;; Read-only Jira Data Center support.

(require 'auth-source)
(require 'cl-lib)
(require 'json)
(require 'seq)
(require 'subr-x)
(require 'url)
(require 'url-http)
(require 'url-util)

(defvar url-http-end-of-headers)
(defvar url-http-response-status)

(defgroup my-jira nil
  "Read-only access to Jira from Emacs."
  :group 'tools)

(defcustom my/jira-base-url "https://jira.drwholdings.com"
  "Base URL for the Jira Data Center instance, without a trailing slash."
  :type 'string
  :group 'my-jira)

(defcustom my/jira-auth-user "jira-pat"
  "Login used to find the Jira PAT in `auth-source'."
  :type 'string
  :group 'my-jira)

(defcustom my/jira-seed-jql
  "assignee = currentUser() OR watcher = currentUser()"
  "JQL selecting the initial set of issues for the local Jira graph."
  :type 'string
  :group 'my-jira)

(defcustom my/jira-request-timeout 30
  "Seconds to wait for a Jira request before giving up."
  :type 'integer
  :group 'my-jira)

(defcustom my/jira-page-size 100
  "Number of issues requested from Jira in each search page."
  :type 'integer
  :group 'my-jira)

(defcustom my/jira-node-directory
  (expand-file-name
   "work/jira/"
   (if (boundp 'org-roam-directory)
       org-roam-directory
     "~/agenda/roam/"))
  "Directory containing generated Jira Org-roam issue nodes."
  :type 'directory
  :group 'my-jira)

(defcustom my/jira-epic-link-field "customfield_10010"
  "Jira custom field ID containing a story's epic key.

The default is the Epic Link field reported by `my/jira-diagnose'."
  :type '(choice (const :tag "Not configured" nil) string)
  :group 'my-jira)

(defcustom my/jira-parent-link-field "customfield_14202"
  "Jira custom field ID containing an Advanced Roadmaps parent."
  :type '(choice (const :tag "Not configured" nil) string)
  :group 'my-jira)

(defcustom my/jira-dashboard-file
  (expand-file-name
   "work/jira-dashboard.org"
   (if (boundp 'org-roam-directory)
       org-roam-directory
     "~/agenda/roam/"))
  "Generated Org dashboard for Jira issues."
  :type 'file
  :group 'my-jira)

(defcustom my/jira-confirm-write-count 250
  "Ask before an interactive refresh writes more than this many nodes."
  :type 'integer
  :group 'my-jira)

(defcustom my/jira-write-batch-size 25
  "Number of Org files written before yielding back to Emacs."
  :type 'integer
  :group 'my-jira)

(defcustom my/jira-write-batch-delay 0.01
  "Seconds to yield between batches of generated Org files."
  :type 'number
  :group 'my-jira)

(defcustom my/jira-index-written-nodes t
  "When non-nil, incrementally update Org-roam after writing each node."
  :type 'boolean
  :group 'my-jira)

(defconst my/jira--diagnostic-buffer "*Jira Diagnostic*")

(cl-defstruct (my/jira-operation
               (:constructor my/jira--make-operation))
  id kind phase canceled request-buffer request-timer work-timer
  issues pending-issues written-files started-at)

(defvar my/jira--active-operation nil
  "The currently running Jira operation, or nil.")

(defun my/jira--host ()
  "Return the hostname from `my/jira-base-url'."
  (or (url-host (url-generic-parse-url my/jira-base-url))
      (user-error "Invalid `my/jira-base-url': %s" my/jira-base-url)))

(defun my/jira--pat ()
  "Return the Jira PAT obtained from `auth-source'."
  (let* ((entry (car (auth-source-search
                      :host (my/jira--host)
                      :user my/jira-auth-user
                      :require '(:secret)
                      :max 1)))
         (secret (plist-get entry :secret))
         (value (if (functionp secret) (funcall secret) secret)))
    (unless (and (stringp value) (not (string-empty-p value)))
      (user-error
       "No Jira PAT found for host %s and login %s"
       (my/jira--host) my/jira-auth-user))
    value))

(defun my/jira--url (path &optional query)
  "Build a Jira URL for PATH and optional QUERY alist."
  (concat (string-remove-suffix "/" my/jira-base-url)
          "/" (string-remove-prefix "/" path)
          (when query
            (concat "?" (url-build-query-string query)))))

(defun my/jira--operation-live-p (operation)
  "Return non-nil when OPERATION is active and has not been canceled."
  (and (eq operation my/jira--active-operation)
       (not (my/jira-operation-canceled operation))))

(defun my/jira--cancel-timer (timer)
  "Cancel TIMER when it is a live timer."
  (when (timerp timer)
    (cancel-timer timer)))

(defun my/jira--clear-request (operation)
  "Clear OPERATION's current HTTP request bookkeeping."
  (my/jira--cancel-timer (my/jira-operation-request-timer operation))
  (setf (my/jira-operation-request-buffer operation) nil
        (my/jira-operation-request-timer operation) nil))

(defun my/jira--finish-operation (operation message-text)
  "Finish OPERATION successfully and display MESSAGE-TEXT."
  (when (eq operation my/jira--active-operation)
    (my/jira--clear-request operation)
    (my/jira--cancel-timer (my/jira-operation-work-timer operation))
    (setf (my/jira-operation-work-timer operation) nil)
    (setq my/jira--active-operation nil)
    (message "%s" message-text)))

(defun my/jira--fail-operation (operation error-text)
  "Stop OPERATION and report ERROR-TEXT without modifying the dashboard."
  (when (eq operation my/jira--active-operation)
    (my/jira--clear-request operation)
    (my/jira--cancel-timer (my/jira-operation-work-timer operation))
    (setf (my/jira-operation-canceled operation) t
          (my/jira-operation-work-timer operation) nil)
    (setq my/jira--active-operation nil)
    (message "Jira %s failed: %s"
             (my/jira-operation-kind operation) error-text)))

(defun my/jira--request-timeout (operation buffer path on-error)
  "Cancel OPERATION's request BUFFER for PATH and call ON-ERROR."
  (when (and (my/jira--operation-live-p operation)
             (eq buffer (my/jira-operation-request-buffer operation)))
    (when (buffer-live-p buffer)
      (kill-buffer buffer))
    (my/jira--clear-request operation)
    (funcall on-error (format "Request timed out after %ss: %s"
                              my/jira-request-timeout path))))

(defun my/jira--handle-json-response
    (status operation buffer path on-success on-error)
  "Handle an asynchronous Jira response in BUFFER.

STATUS is supplied by `url-retrieve'. OPERATION owns the request. PATH is used
only for sanitized errors. ON-SUCCESS receives parsed JSON; ON-ERROR receives
an error string."
  (when (buffer-live-p buffer)
    (let (result error-text)
      (unwind-protect
          (when (my/jira--operation-live-p operation)
            (cond
             ((plist-get status :error)
              (setq error-text (format "Network error requesting %s: %s"
                                       path (plist-get status :error))))
             ((not (and (integerp url-http-response-status)
                        (<= 200 url-http-response-status)
                        (< url-http-response-status 300)))
              (setq error-text
                    (format "Request %s returned HTTP %s"
                            path (or url-http-response-status "unknown"))))
             (t
              (condition-case err
                  (progn
                    (goto-char url-http-end-of-headers)
                    (setq result
                          (json-parse-buffer
                           :object-type 'alist
                           :array-type 'list
                           :null-object nil
                           :false-object nil)))
                (error
                 (setq error-text
                       (format "Invalid JSON from %s: %s"
                               path (error-message-string err))))))))
        (when (eq buffer (my/jira-operation-request-buffer operation))
          (my/jira--clear-request operation))
        (kill-buffer buffer))
      (when (my/jira--operation-live-p operation)
        (condition-case err
            (if error-text
                (funcall on-error error-text)
              (funcall on-success result))
          (quit
           (my/jira--fail-operation operation "Canceled by user"))
          (error
           (my/jira--fail-operation operation
                                    (error-message-string err))))))))

(defun my/jira--get-json-async
    (operation path query on-success on-error)
  "Asynchronously GET Jira PATH with QUERY for OPERATION.

ON-SUCCESS receives parsed JSON. ON-ERROR receives a sanitized error string.
The credential and response are never written to disk."
  (when (my/jira--operation-live-p operation)
    (condition-case err
        (let* ((url-request-method "GET")
               (url-request-extra-headers
                `(("Authorization" . ,(concat "Bearer " (my/jira--pat)))
                  ("Accept" . "application/json")))
               (url-user-agent "Emacs Jira read-only client")
               (request-url (my/jira--url path query))
               buffer)
          (setq buffer
                (url-retrieve
                 request-url
                 (lambda (status)
                   (my/jira--handle-json-response
                    status operation (current-buffer) path
                    on-success on-error))
                 nil t t))
          (unless (buffer-live-p buffer)
            (error "Could not start request"))
          (setf (my/jira-operation-request-buffer operation) buffer
                (my/jira-operation-request-timer operation)
                (run-at-time my/jira-request-timeout nil
                             #'my/jira--request-timeout
                             operation buffer path on-error)))
      (error
       (funcall on-error
                (format "Could not request %s: %s"
                        path (error-message-string err)))))))

(defun my/jira--search-fields ()
  "Return the Jira fields needed by the importer."
  (string-join
   (append '("summary" "status" "issuetype" "assignee" "updated"
             "parent" "issuelinks" "project")
           (delq nil (list my/jira-epic-link-field
                           my/jira-parent-link-field)))
   ","))

(defun my/jira--search-all-async
    (operation jql label on-success on-error &optional start issues)
  "Asynchronously retrieve every Jira issue matching JQL.

LABEL describes this search in progress messages. ON-SUCCESS receives all
issues and ON-ERROR receives an error string. START and ISSUES are internal
pagination state."
  (let ((start (or start 0))
        (issues (or issues nil)))
    (my/jira--get-json-async
     operation "/rest/api/2/search"
     `(("jql" ,jql)
       ("startAt" ,(number-to-string start))
       ("maxResults" ,(number-to-string my/jira-page-size))
       ("fields" ,(my/jira--search-fields)))
     (lambda (response)
       (let* ((page (alist-get 'issues response))
              (total (or (alist-get 'total response) 0))
              (next-issues (nconc issues (copy-sequence page)))
              (next-start (+ start (length page))))
         (message "Jira refresh: %s %d/%d" label next-start total)
         (cond
          ((>= next-start total)
           (funcall on-success next-issues))
          ((null page)
           (funcall on-error
                    (format "Jira returned an empty page at %d/%d for %s"
                            next-start total label)))
          (t
           (my/jira--search-all-async
            operation jql label on-success on-error next-start next-issues)))))
     on-error)))

(defun my/jira--issue-key (issue)
  "Return ISSUE's Jira key."
  (alist-get 'key issue))

(defun my/jira--valid-key-p (key)
  "Return non-nil when KEY has the shape of a Jira issue key."
  (and (stringp key)
       (string-match-p (rx string-start
                           upper
                           (+ (or upper digit "_"))
                           "-" (+ digit)
                           string-end)
                       key)))

(defun my/jira--issue-link-keys (issue)
  "Return keys of issues explicitly linked to ISSUE."
  (let* ((fields (alist-get 'fields issue))
         (links (alist-get 'issuelinks fields)))
    (delete-dups
     (delq nil
           (mapcar
            (lambda (link)
              (my/jira--issue-key
               (or (alist-get 'inwardIssue link)
                   (alist-get 'outwardIssue link))))
            links)))))

(defun my/jira--field-issue-key (value)
  "Extract a Jira issue key from custom field VALUE."
  (cond ((and (stringp value) (my/jira--valid-key-p value)) value)
        ((listp value)
         (let ((key (alist-get 'key value)))
           (and (my/jira--valid-key-p key) key)))))

(defun my/jira--issue-type (issue)
  "Return ISSUE's issue type name."
  (alist-get 'name (alist-get 'issuetype (alist-get 'fields issue))))

(defun my/jira--epic-p (issue)
  "Return non-nil when ISSUE is an Epic."
  (string-equal (downcase (or (my/jira--issue-type issue) "")) "epic"))

(defun my/jira--jql-key-list (keys)
  "Format KEYS for a JQL `key in (...)' expression."
  (unless (seq-every-p #'my/jira--valid-key-p keys)
    (error "Refusing to interpolate an invalid Jira key into JQL"))
  (concat "key in (" (string-join keys ", ") ")"))

(defun my/jira--custom-field-number (field)
  "Return the numeric suffix from a Jira custom FIELD ID."
  (when (and field
             (string-match (rx string-start "customfield_" (group (+ digit))
                               string-end)
                           field))
    (match-string 1 field)))

(defun my/jira--epic-children-jql (epic-keys)
  "Return JQL selecting children of EPIC-KEYS."
  (let ((number (my/jira--custom-field-number my/jira-epic-link-field)))
    (unless number
      (user-error "`my/jira-epic-link-field' is not configured"))
    (concat "cf[" number "] in (" (string-join epic-keys ", ") ")")))

(defun my/jira--chunks (items size)
  "Split ITEMS into lists containing at most SIZE elements."
  (let (chunks)
    (while items
      (let ((chunk nil))
        (dotimes (_ size)
          (when items
            (push (pop items) chunk)))
        (push (nreverse chunk) chunks)))
    (nreverse chunks)))

(defun my/jira--deduplicate-issues (issues)
  "Return ISSUES once each, preserving their first occurrence."
  (let ((seen (make-hash-table :test #'equal))
        result)
    (dolist (issue issues (nreverse result))
      (let ((key (my/jira--issue-key issue)))
        (unless (gethash key seen)
          (puthash key t seen)
          (push issue result))))))

(defun my/jira--run-search-jobs-async
    (operation jobs issues completed total on-success on-error)
  "Run asynchronous search JOBS sequentially for OPERATION.

Accumulate results after ISSUES. COMPLETED and TOTAL drive progress reporting.
ON-SUCCESS receives the complete issue list. ON-ERROR receives an error
string."
  (if (or (not (my/jira--operation-live-p operation)) (null jobs))
      (when (my/jira--operation-live-p operation)
        (funcall on-success issues))
    (let* ((job (car jobs))
           (jql (plist-get job :jql))
           (label (format "%s batch %d/%d"
                          (plist-get job :label) (1+ completed) total)))
      (my/jira--search-all-async
       operation jql label
       (lambda (job-issues)
         (my/jira--run-search-jobs-async
          operation (cdr jobs) (nconc issues job-issues)
          (1+ completed) total on-success on-error))
       on-error))))

(defun my/jira-fetch-one-hop-graph-async
    (operation on-success on-error)
  "Asynchronously fetch the one-hop Jira graph for OPERATION.

Edges include explicit Jira issue links, a seed issue's parent, and all
children of seed Epics regardless of assignee. ON-SUCCESS receives the
deduplicated issue list; ON-ERROR receives an error string."
  (setf (my/jira-operation-phase operation) 'fetching-seeds)
  (my/jira--search-all-async
   operation my/jira-seed-jql "seed issues"
   (lambda (seeds)
     (when (my/jira--operation-live-p operation)
       (let* ((seed-keys (mapcar #'my/jira--issue-key seeds))
              (linked-keys
               (delete-dups (mapcan #'my/jira--issue-link-keys seeds)))
              (parent-keys
               (delq nil (mapcar #'my/jira--issue-parent-key seeds)))
              (neighbor-keys (delete-dups (append linked-keys parent-keys)))
              (missing-keys
               (seq-remove (lambda (key) (member key seed-keys))
                           neighbor-keys))
              (epic-keys
               (mapcar #'my/jira--issue-key
                       (seq-filter #'my/jira--epic-p seeds)))
              (neighbor-jobs
               (mapcar (lambda (keys)
                         (list :label "linked/parent issues"
                               :jql (my/jira--jql-key-list keys)))
                       (my/jira--chunks missing-keys 50)))
              (child-jobs
               (mapcar (lambda (keys)
                         (list :label "Epic children"
                               :jql (my/jira--epic-children-jql keys)))
                       (my/jira--chunks epic-keys 50)))
              (jobs (append neighbor-jobs child-jobs)))
         (setf (my/jira-operation-phase operation) 'fetching-relations)
         (if jobs
             (my/jira--run-search-jobs-async
              operation jobs seeds 0 (length jobs)
              (lambda (issues)
                (funcall on-success (my/jira--deduplicate-issues issues)))
              on-error)
           (funcall on-success seeds)))))
   on-error))

(defun my/jira--single-line (value)
  "Return VALUE as trimmed single-line text."
  (string-trim
   (replace-regexp-in-string "[\n\r]+" " " (or value ""))))

(defun my/jira--node-id (key)
  "Return the stable Org ID for Jira KEY."
  (concat "jira-" key))

(defun my/jira--browse-url (key)
  "Return the browser URL for Jira KEY."
  (my/jira--url (concat "/browse/" key)))

(defun my/jira--node-file (key)
  "Return the Org-roam filename for Jira KEY."
  (unless (my/jira--valid-key-p key)
    (error "Invalid Jira key: %S" key))
  (expand-file-name (concat key ".org") my/jira-node-directory))

(defun my/jira--existing-notes (file)
  "Return the user-owned Notes subtree from FILE, if present."
  (when (file-readable-p file)
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (when (re-search-forward (rx line-start "* Notes" line-end) nil t)
        (buffer-substring-no-properties (match-beginning 0) (point-max))))))

(defun my/jira--issue-parent-key (issue)
  "Return ISSUE's parent or configured epic key, if present."
  (let* ((fields (alist-get 'fields issue))
         (parent (alist-get 'parent fields))
         (epic-key
          (and my/jira-epic-link-field
               (alist-get (intern my/jira-epic-link-field) fields)))
         (portfolio-parent
          (and my/jira-parent-link-field
               (alist-get (intern my/jira-parent-link-field) fields))))
    (or (my/jira--issue-key parent)
        (my/jira--field-issue-key epic-key)
        (my/jira--field-issue-key portfolio-parent))))

(defun my/jira--render-node (issue &optional notes)
  "Render ISSUE as an Org-roam node while retaining NOTES."
  (let* ((key (my/jira--issue-key issue))
         (fields (alist-get 'fields issue))
         (summary (my/jira--single-line (alist-get 'summary fields)))
         (status (my/jira--single-line
                  (alist-get 'name (alist-get 'status fields))))
         (issue-type (my/jira--single-line
                      (alist-get 'name (alist-get 'issuetype fields))))
         (assignee (my/jira--single-line
                    (alist-get 'displayName (alist-get 'assignee fields))))
         (updated (my/jira--single-line (alist-get 'updated fields)))
         (project (or (alist-get 'key (alist-get 'project fields))
                      (car (split-string key "-"))))
         (parent-key (my/jira--issue-parent-key issue))
         (related-keys (my/jira--issue-link-keys issue))
         (jira-url (my/jira--browse-url key)))
    (concat
     "#    -*- mode: org -*-\n"
     ":PROPERTIES:\n"
     ":ID:       " (my/jira--node-id key) "\n"
     ":ROAM_REFS: " jira-url "\n"
     ":END:\n"
     "#+title: " key " — " summary "\n"
     "#+filetags: :jira:" (downcase project) ":\n\n"
     "* Jira\n"
     ":PROPERTIES:\n"
     ":JIRA_KEY: " key "\n"
     ":JIRA_PROJECT: " project "\n"
     ":JIRA_TYPE: " issue-type "\n"
     ":JIRA_STATUS: " status "\n"
     ":JIRA_ASSIGNEE: " assignee "\n"
     ":JIRA_UPDATED: " updated "\n"
     (if parent-key (concat ":JIRA_PARENT: " parent-key "\n") "")
     ":END:\n"
     "- Jira: [[" jira-url "][" key "]]\n"
     (if parent-key
         (concat "- Parent: [[id:" (my/jira--node-id parent-key)
                 "][" parent-key "]]\n")
       "")
     (if related-keys
         (concat "- Related:\n"
                 (mapconcat
                  (lambda (related-key)
                    (concat "  - [[id:" (my/jira--node-id related-key)
                            "][" related-key "]]"))
                  related-keys "\n")
                 "\n")
       "")
     "\n"
     (or notes "* Notes\n"))))

(defun my/jira--write-node (issue)
  "Write ISSUE to its Org-roam node, preserving its Notes subtree."
  (let* ((key (my/jira--issue-key issue))
         (file (my/jira--node-file key))
         (notes (my/jira--existing-notes file))
         (content (my/jira--render-node issue notes))
         temporary-file)
    (make-directory my/jira-node-directory t)
    (setq temporary-file
          (make-temp-file (expand-file-name ".jira-node-"
                                           my/jira-node-directory)))
    (unwind-protect
        (progn
          (with-temp-file temporary-file
            (insert content))
          (rename-file temporary-file file t)
          (setq temporary-file nil))
      (when (and temporary-file (file-exists-p temporary-file))
        (delete-file temporary-file)))
    file))

(defun my/jira--dashboard-archive-file ()
  "Return the default archive filename for the Jira dashboard."
  (concat my/jira-dashboard-file "_archive"))

(defun my/jira--archived-keys ()
  "Return Jira keys recorded in the dashboard archive file."
  (let ((file (my/jira--dashboard-archive-file))
        keys)
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (re-search-forward
                (rx line-start ":JIRA_KEY:" (+ blank)
                    (group upper (+ (or upper digit "_")) "-" (+ digit))
                    (* blank) line-end)
                nil t)
          (push (match-string-no-properties 1) keys))))
    (delete-dups keys)))

(defun my/jira--issue-project (issue)
  "Return ISSUE's project key."
  (let ((key (my/jira--issue-key issue)))
    (or (alist-get 'key (alist-get 'project (alist-get 'fields issue)))
        (car (split-string key "-")))))

(defun my/jira--issue-summary (issue)
  "Return ISSUE's summary as one line."
  (my/jira--single-line (alist-get 'summary (alist-get 'fields issue))))

(defun my/jira--issue-status (issue)
  "Return ISSUE's status name."
  (my/jira--single-line
   (alist-get 'name (alist-get 'status (alist-get 'fields issue)))))

(defun my/jira--issue-assignee (issue)
  "Return ISSUE's assignee display name."
  (my/jira--single-line
   (alist-get 'displayName (alist-get 'assignee (alist-get 'fields issue)))))

(defun my/jira--insert-dashboard-issue (issue level &optional children)
  "Insert ISSUE at Org LEVEL, followed by optional CHILDREN."
  (let* ((key (my/jira--issue-key issue))
         (summary (my/jira--issue-summary issue))
         (status (my/jira--issue-status issue))
         (assignee (my/jira--issue-assignee issue))
         (related (my/jira--issue-link-keys issue)))
    (insert (make-string level ?*) " " key " — "
            "[[id:" (my/jira--node-id key) "][" summary "]]\n")
    (insert ":PROPERTIES:\n:JIRA_KEY: " key "\n:END:\n")
    (insert "- Type: " (or (my/jira--issue-type issue) "")
            "; Status: " status)
    (unless (string-empty-p assignee)
      (insert "; Assignee: " assignee))
    (insert "\n")
    (when related
      (insert "- Related: ")
      (insert
       (mapconcat
        (lambda (related-key)
          (format "%s ([[id:%s][node]])"
                  related-key (my/jira--node-id related-key)))
        related ", "))
      (insert "\n"))
    (dolist (child (sort (copy-sequence children)
                         (lambda (a b)
                           (string-lessp (my/jira--issue-key a)
                                         (my/jira--issue-key b)))))
      (my/jira--insert-dashboard-issue child (1+ level)))))

(defun my/jira--render-dashboard (issues)
  "Render ISSUES as an Epic-to-Story Org dashboard."
  (let ((issue-table (make-hash-table :test #'equal))
        (children-table (make-hash-table :test #'equal))
        (project-table (make-hash-table :test #'equal))
        (archived (my/jira--archived-keys)))
    (dolist (issue issues)
      (unless (member (my/jira--issue-key issue) archived)
        (puthash (my/jira--issue-key issue) issue issue-table)))
    (maphash
     (lambda (_key issue)
       (let* ((parent-key (my/jira--issue-parent-key issue))
              (parent (and parent-key (gethash parent-key issue-table))))
         (if (and parent (my/jira--epic-p parent))
             (puthash parent-key
                      (cons issue (gethash parent-key children-table))
                      children-table)
           (let ((project (my/jira--issue-project issue)))
             (puthash project
                      (cons issue (gethash project project-table))
                      project-table)))))
     issue-table)
    (with-temp-buffer
      (insert "#    -*- mode: org -*-\n"
              "#+title: Jira Dashboard\n"
              "#+startup: overview\n\n"
              "This file is generated by =my/jira-refresh=. "
              "Archive issue subtrees normally; archived keys are not regenerated.\n\n")
      (dolist (project (sort (hash-table-keys project-table) #'string-lessp))
        (let ((roots (gethash project project-table)))
          (insert "* " project "\n")
          (insert (format "  %d top-level issue%s\n"
                          (length roots) (if (= (length roots) 1) "" "s")))
          (dolist (issue (sort (copy-sequence roots)
                               (lambda (a b)
                                 (string-lessp (my/jira--issue-key a)
                                               (my/jira--issue-key b)))))
            (my/jira--insert-dashboard-issue
             issue 2 (gethash (my/jira--issue-key issue) children-table)))))
      (buffer-string))))

(defun my/jira--write-dashboard (issues)
  "Atomically write the Jira dashboard for ISSUES."
  (let* ((directory (file-name-directory my/jira-dashboard-file))
         (content (my/jira--render-dashboard issues))
         temporary-file)
    (make-directory directory t)
    (setq temporary-file (make-temp-file
                          (expand-file-name ".jira-dashboard-" directory)))
    (unwind-protect
        (progn
          (with-temp-file temporary-file
            (insert content))
          (rename-file temporary-file my/jira-dashboard-file t)
          (setq temporary-file nil))
      (when (and temporary-file (file-exists-p temporary-file))
        (delete-file temporary-file)))
    my/jira-dashboard-file))

;;;###autoload
(defun my/jira--start-operation (kind)
  "Start and return a Jira operation of KIND."
  (when my/jira--active-operation
    (user-error "A Jira %s is already running; use `my/jira-cancel' first"
                (my/jira-operation-kind my/jira--active-operation)))
  (let ((operation
         (my/jira--make-operation
          :id (format-time-string "%Y%m%dT%H%M%S.%3N")
          :kind kind
          :phase 'starting
          :started-at (float-time))))
    (setq my/jira--active-operation operation)
    operation))

(defun my/jira--index-file (file)
  "Incrementally update Org-roam's database for FILE when configured."
  (when (and my/jira-index-written-nodes
             (fboundp 'org-roam-db-update-file))
    (condition-case err
        (org-roam-db-update-file file)
      (error
       (message "Jira refresh: Org-roam could not index %s: %s"
                (file-name-nondirectory file) (error-message-string err))))))

(defun my/jira--schedule-write-batch (operation)
  "Schedule the next non-blocking file-write batch for OPERATION."
  (when (my/jira--operation-live-p operation)
    (setf (my/jira-operation-work-timer operation)
          (run-at-time my/jira-write-batch-delay nil
                       #'my/jira--write-next-batch operation))))

(defun my/jira--write-next-batch (operation)
  "Write one batch of generated nodes for OPERATION, then yield."
  (when (my/jira--operation-live-p operation)
    (setf (my/jira-operation-work-timer operation) nil
          (my/jira-operation-phase operation) 'writing-nodes)
    (condition-case err
        (progn
          (dotimes (_ my/jira-write-batch-size)
            (when (my/jira-operation-pending-issues operation)
              (let* ((issue (pop (my/jira-operation-pending-issues operation)))
                     (file (my/jira--write-node issue)))
                (push file (my/jira-operation-written-files operation))
                (my/jira--index-file file))))
          (let ((written (length (my/jira-operation-written-files operation)))
                (total (length (my/jira-operation-issues operation))))
            (message "Jira refresh: wrote %d/%d nodes" written total))
          (if (my/jira-operation-pending-issues operation)
              (my/jira--schedule-write-batch operation)
            (setf (my/jira-operation-phase operation) 'writing-dashboard)
            (let ((dashboard
                   (my/jira--write-dashboard
                    (my/jira-operation-issues operation))))
              (my/jira--index-file dashboard))
            (let* ((count (length (my/jira-operation-written-files operation)))
                   (elapsed (- (float-time)
                               (my/jira-operation-started-at operation))))
              (my/jira--finish-operation
               operation
               (format "Refreshed %d Jira nodes and dashboard in %.1fs"
                       count elapsed)))))
      (quit
       (my/jira-cancel))
      (error
       (my/jira--fail-operation operation (error-message-string err))))))

;;;###autoload
(defun my/jira-refresh ()
  "Asynchronously refresh Jira Org-roam nodes and the dashboard.

The command returns immediately while paginated GET requests run in the
background. No files are changed unless every required request succeeds.
Node writes are split into batches so Emacs can process input between them.
Each node's `* Notes' subtree survives refreshes."
  (interactive)
  (let ((operation (my/jira--start-operation 'refresh)))
    (message "Jira refresh: fetching seed issues asynchronously...")
    (condition-case err
        (my/jira-fetch-one-hop-graph-async
         operation
         (lambda (issues)
           (when (my/jira--operation-live-p operation)
             (if (and (> (length issues) my/jira-confirm-write-count)
                      (not (yes-or-no-p
                            (format "Refresh %d Jira nodes? "
                                    (length issues)))))
                 (my/jira-cancel)
               (setf (my/jira-operation-issues operation) issues
                     (my/jira-operation-pending-issues operation)
                     (copy-sequence issues)
                     (my/jira-operation-phase operation) 'writing-nodes)
               (message "Jira refresh: all requests succeeded; writing nodes...")
               (my/jira--schedule-write-batch operation))))
         (lambda (error-text)
           (my/jira--fail-operation operation error-text)))
      (quit
       (my/jira-cancel))
      (error
       (my/jira--fail-operation operation (error-message-string err))))
    operation))

(defalias 'my/jira-refresh-nodes #'my/jira-refresh)

;;;###autoload
(defun my/jira-cancel ()
  "Cancel the active Jira request or refresh."
  (interactive)
  (if-let ((operation my/jira--active-operation))
      (progn
        (setf (my/jira-operation-canceled operation) t)
        (when-let ((buffer (my/jira-operation-request-buffer operation)))
          (when (buffer-live-p buffer)
            (kill-buffer buffer)))
        (my/jira--clear-request operation)
        (my/jira--cancel-timer (my/jira-operation-work-timer operation))
        (setf (my/jira-operation-work-timer operation) nil)
        (setq my/jira--active-operation nil)
        (message "Canceled Jira %s during %s"
                 (my/jira-operation-kind operation)
                 (my/jira-operation-phase operation)))
    (message "No Jira operation is running")))

;;;###autoload
(defun my/jira-status ()
  "Describe the active Jira operation."
  (interactive)
  (if-let ((operation my/jira--active-operation))
      (message "Jira %s is running (%s, %.1fs elapsed)"
               (my/jira-operation-kind operation)
               (my/jira-operation-phase operation)
               (- (float-time) (my/jira-operation-started-at operation)))
    (message "No Jira operation is running")))

(defconst my/jira--key-regexp
  (rx word-start upper (+ (or upper digit "_")) "-" (+ digit) word-end))

(defun my/jira--key-bounds-at-point ()
  "Return bounds of a Jira issue key at point, or nil."
  (let ((origin (point))
        (limit (line-end-position)))
    (save-excursion
      (goto-char (line-beginning-position))
      (catch 'bounds
        (while (re-search-forward my/jira--key-regexp limit t)
          (when (and (<= (match-beginning 0) origin)
                     (<= origin (match-end 0)))
            (throw 'bounds (cons (match-beginning 0) (match-end 0)))))))))

(defun my/jira-browse-key-at-point ()
  "Open the Jira issue key at point in the configured browser."
  (interactive)
  (if-let ((bounds (my/jira--key-bounds-at-point)))
      (browse-url
       (my/jira--browse-url
        (buffer-substring-no-properties (car bounds) (cdr bounds))))
    (user-error "No Jira issue key at point")))

(defun my/jira--install-hyperbole-button ()
  "Install the Jira issue-key implicit button type in Hyperbole."
  (eval
   '(defib my-jira-issue-key ()
      "Open a Jira issue key at point in the external browser."
      (when-let ((bounds (my/jira--key-bounds-at-point)))
        (let ((key (buffer-substring-no-properties
                    (car bounds) (cdr bounds))))
          (ibut:label-set key (car bounds) (cdr bounds))
          (hact #'browse-url (my/jira--browse-url key)))))))

(with-eval-after-load 'hyperbole
  (my/jira--install-hyperbole-button))

(defun my/jira--field-candidates (fields)
  "Return hierarchy-related Jira FIELDS."
  (seq-filter
   (lambda (field)
     (string-match-p
      (rx (or "epic" "parent" "portfolio" "initiative"))
      (downcase (or (alist-get 'name field) ""))))
   fields))

(defun my/jira--insert-field-report (fields)
  "Insert a diagnostic summary of hierarchy-related FIELDS."
  (insert "Hierarchy-related fields:\n")
  (if-let ((candidates (my/jira--field-candidates fields)))
      (dolist (field candidates)
        (insert (format "  %-24s %s\n"
                        (or (alist-get 'id field) "<no id>")
                        (or (alist-get 'name field) "<unnamed>"))))
    (insert "  None found\n")))

(defun my/jira--insert-link-type-report (response)
  "Insert issue-link types from RESPONSE."
  (insert "\nIssue link types:\n")
  (if-let ((types (alist-get 'issueLinkTypes response)))
      (dolist (type types)
        (insert (format "  %s: %s / %s\n"
                        (or (alist-get 'name type) "<unnamed>")
                        (or (alist-get 'inward type) "<no inward label>")
                        (or (alist-get 'outward type) "<no outward label>"))))
    (insert "  None returned\n")))

;;;###autoload
(defun my/jira--render-diagnostic (responses)
  "Render a sanitized diagnostic report from RESPONSES."
  (let* ((server (alist-get 'server responses))
         (user (alist-get 'user responses))
         (fields (alist-get 'fields responses))
         (link-types (alist-get 'link-types responses))
         (search (alist-get 'search responses))
         (sample (car (alist-get 'issues search)))
         (sample-fields (alist-get 'fields sample))
         (issue-type (alist-get 'name (alist-get 'issuetype sample-fields)))
         (parent (alist-get 'parent sample-fields))
         (links (alist-get 'issuelinks sample-fields)))
    (with-current-buffer (get-buffer-create my/jira--diagnostic-buffer)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert "Jira diagnostic\n===============\n\n")
        (insert (format "Base URL:          %s\n" my/jira-base-url))
        (insert (format "Server title:      %s\n"
                        (or (alist-get 'serverTitle server) "<unknown>")))
        (insert (format "Server version:    %s\n"
                        (or (alist-get 'version server) "<unknown>")))
        (insert (format "Authenticated as:  %s\n"
                        (or (alist-get 'displayName user)
                            (alist-get 'name user)
                            "<unknown>")))
        (insert (format "Seed issue count:  %s\n"
                        (or (alist-get 'total search) 0)))
        (when sample
          (insert (format "Sample issue type: %s\n"
                          (or issue-type "<unknown>")))
          (insert (format "Sample has parent: %s\n" (if parent "yes" "no")))
          (insert (format "Sample link count: %d\n" (length links))))
        (insert "\n")
        (my/jira--insert-field-report fields)
        (my/jira--insert-link-type-report link-types)
        (goto-char (point-min))
        (special-mode))
      (display-buffer (current-buffer)))
    my/jira--diagnostic-buffer))

(defun my/jira--run-json-jobs-async
    (operation jobs responses completed on-success on-error)
  "Run diagnostic JSON JOBS asynchronously for OPERATION.

RESPONSES accumulates keyed results. COMPLETED is used for progress.
ON-SUCCESS receives all responses; ON-ERROR receives an error string."
  (if (or (not (my/jira--operation-live-p operation)) (null jobs))
      (when (my/jira--operation-live-p operation)
        (funcall on-success responses))
    (let* ((job (car jobs))
           (key (plist-get job :key))
           (path (plist-get job :path))
           (query (plist-get job :query))
           (total (+ completed (length jobs))))
      (setf (my/jira-operation-phase operation) key)
      (message "Jira diagnostic: request %d/%d" (1+ completed) total)
      (my/jira--get-json-async
       operation path query
       (lambda (response)
         (my/jira--run-json-jobs-async
          operation (cdr jobs) (cons (cons key response) responses)
          (1+ completed) on-success on-error))
       on-error))))

;;;###autoload
(defun my/jira-diagnose ()
  "Asynchronously verify Jira access and report the relevant schema.

The report includes server metadata, the number of seed issues, hierarchy
field identifiers, and issue-link type names. It never displays the PAT,
issue summaries, descriptions, comments, or issue keys."
  (interactive)
  (let* ((operation (my/jira--start-operation 'diagnostic))
         (jobs
          `((:key server :path "/rest/api/2/serverInfo")
            (:key user :path "/rest/api/2/myself")
            (:key fields :path "/rest/api/2/field")
            (:key link-types :path "/rest/api/2/issueLinkType")
            (:key search :path "/rest/api/2/search"
             :query (("jql" ,my/jira-seed-jql)
                     ("maxResults" "1")
                     ("fields" "issuetype,parent,issuelinks"))))))
    (message "Checking Jira connectivity and schema asynchronously...")
    (condition-case err
        (my/jira--run-json-jobs-async
         operation jobs nil 0
         (lambda (responses)
           (my/jira--render-diagnostic responses)
           (my/jira--finish-operation operation "Jira diagnostic succeeded"))
         (lambda (error-text)
           (my/jira--fail-operation operation error-text)))
      (quit
       (my/jira-cancel))
      (error
       (my/jira--fail-operation operation (error-message-string err))))
    operation))

(provide 'my-jira)
;;; jira.el ends here
