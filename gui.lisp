;;; -*- Mode: Lisp; Package: CLIMACS-GUI -*-

;;;  (c) copyright 2004 by
;;;           Robert Strandh (strandh@labri.fr)
;;;  (c) copyright 2004 by
;;;           Elliott Johnson (ejohnson@fasl.info)

;;; This library is free software; you can redistribute it and/or
;;; modify it under the terms of the GNU Library General Public
;;; License as published by the Free Software Foundation; either
;;; version 2 of the License, or (at your option) any later version.
;;;
;;; This library is distributed in the hope that it will be useful,
;;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;;; Library General Public License for more details.
;;;
;;; You should have received a copy of the GNU Library General Public
;;; License along with this library; if not, write to the
;;; Free Software Foundation, Inc., 59 Temple Place - Suite 330,
;;; Boston, MA  02111-1307  USA.

;;; GUI for the Climacs editor. 

(in-package :climacs-gui)

(defclass filename-mixin ()
  ((filename :initform nil :accessor filename)))

(defclass climacs-buffer (standard-buffer abbrev-mixin filename-mixin) ())

(defclass climacs-pane (application-pane)
  ((buffer :initform (make-instance 'climacs-buffer) :accessor buffer)
   (point :initform nil :initarg :point :reader point)
   (syntax :initarg :syntax :accessor syntax)))

(defmethod initialize-instance :after ((pane climacs-pane) &rest args)
  (declare (ignore args))
  (with-slots (buffer point syntax) pane
     (when (null point)
       (setf point (make-instance 'standard-right-sticky-mark
		      :buffer buffer)))
     (setf syntax (make-instance 'texinfo-syntax :buffer buffer :pane pane))))

(define-application-frame climacs ()
  ((win :reader win))
  (:panes
   (win (make-pane 'climacs-pane
		   :width 600 :height 400
		   :name 'win
		   :display-function 'display-win))
   (int :interactor :width 600 :height 50))
  (:layouts
   (default
       (vertically ()
	 (scrolling (:width 600 :height 400) win)
	 int)))
  (:top-level (climacs-top-level)))

(defun climacs ()
  "Starts up a climacs session"
  (let ((frame (make-application-frame 'climacs)))
    (run-frame-top-level frame)))

(defun display-win (frame pane)
  "The display function used by the climacs application frame."
  (declare (ignore frame))
  (redisplay-with-syntax pane (syntax pane)))

(defun find-gestures (gestures start-table)
  (loop with table = (find-command-table start-table)
	for (gesture . rest) on gestures
	for item = (find-keystroke-item  gesture table :errorp nil)
	while item
	do (if (eq (command-menu-item-type item) :command)
	       (return (if (null rest) item nil))
	       (setf table (command-menu-item-value item)))
	finally (return item)))

(defparameter *current-gesture* nil)

(defun climacs-top-level (frame &key
			  command-parser command-unparser 
			  partial-command-parser prompt)
  (declare (ignore command-parser command-unparser partial-command-parser prompt))
  (setf (slot-value frame 'win) (find-pane-named frame 'win))
  (let ((*standard-output* (frame-standard-output frame))
	(*standard-input* (frame-standard-input frame))
	(*print-pretty* nil))
    (redisplay-frame-panes frame :force-p t)
    (loop with gestures = '()
	  do (setf *current-gesture* (read-gesture :stream *standard-input*))
	     (when (or (characterp *current-gesture*)
		       (and (typep *current-gesture* 'keyboard-event)
			    (keyboard-event-character *current-gesture*)))
	       (setf gestures (nconc gestures (list *current-gesture*)))
	       (let ((item (find-gestures gestures 'global-climacs-table)))
		 (cond ((not item)
			(beep) (setf gestures '()))
		       ((eq (command-menu-item-type item) :command)
			(handler-case 
			    (funcall (command-menu-item-value item))
			  (error (condition)
			    (beep)
			    (format *error-output* "~a~%" condition)))
			(setf gestures '()))
		       (t nil))))
	     (redisplay-frame-panes frame :force-p t))))

(define-command com-quit ()
  (frame-exit *application-frame*))

(define-command com-self-insert ()
  (unless (constituentp *current-gesture*)
    (possibly-expand-abbrev (point (win *application-frame*))))
  (insert-object (point (win *application-frame*)) *current-gesture*))

(define-command com-backward-object ()
  (decf (offset (point (win *application-frame*)))))

(define-command com-forward-object ()
  (incf (offset (point (win *application-frame*)))))

(define-command com-beginning-of-line ()
  (beginning-of-line (point (win *application-frame*))))

(define-command com-end-of-line ()
  (end-of-line (point (win *application-frame*))))

(define-command com-delete-object ()
  (delete-range (point (win *application-frame*))))

(define-command com-previous-line ()
  (previous-line (point (win *application-frame*))))

(define-command com-next-line ()
  (next-line (point (win *application-frame*))))

(define-command com-open-line ()
  (open-line (point (win *application-frame*))))

(define-command com-kill-line ()
  (kill-line (point (win *application-frame*))))

(define-command com-forward-word ()
  (forward-word (point (win *application-frame*))))

(define-command com-backward-word ()
  (backward-word (point (win *application-frame*))))

(define-command com-toggle-layout ()
  (setf (frame-current-layout *application-frame*)
	(if (eq (frame-current-layout *application-frame*) 'default)
	    'with-interactor
	    'default)))

(define-command com-extended-command ()
  (accept 'command :prompt "Extended Command"))

(defclass weird () ()
  (:documentation "An open ended class."))

(define-command com-insert-weird-stuff ()
  (insert-object (point (win *application-frame*)) (make-instance 'weird)))

(define-command com-insert-reversed-string ()
  (insert-sequence (point (win *application-frame*))
		   (reverse (accept 'string))))

(define-presentation-type completable-pathname ()
  :inherit-from 'pathname)

(defun filename-completer (so-far mode)
  (flet ((remove-trail (s)
	   (subseq s 0 (let ((pos (position #\/ s :from-end t)))
			 (if pos (1+ pos) 0)))))
    (let* ((directory-prefix
	    (if (and (plusp (length so-far)) (eql (aref so-far 0) #\/))
		""
		(namestring #+sbcl (car (directory ".")) #+cmu (ext:default-directory))))
	   (full-so-far (concatenate 'string directory-prefix so-far))
	   (pathnames
	    (loop with length = (length full-so-far)
		  for path in (directory (concatenate 'string
						       (remove-trail so-far)
						      "*.*"))
		  when (let ((mismatch (mismatch (namestring path) full-so-far)))
			 (or (null mismatch) (= mismatch length)))
		    collect path))
	   (strings (mapcar #'namestring pathnames))
	   (first-string (car strings))
	   (length-common-prefix nil)
	   (completed-string nil)
	   (full-completed-string nil))
      (unless (null pathnames)
	(setf length-common-prefix
	      (loop with length = (length first-string)
		    for string in (cdr strings)
		    do (setf length (min length (or (mismatch string first-string) length)))
		    finally (return length))))
      (unless (null pathnames)
	(setf completed-string
	      (subseq first-string (length directory-prefix)
		      (if (null (cdr pathnames)) nil length-common-prefix)))
	(setf full-completed-string
	      (concatenate 'string directory-prefix completed-string)))
      (case mode
	((:complete-limited :complete-maximal)
	 (cond ((null pathnames)
		(values so-far nil nil 0 nil))
	       ((null (cdr pathnames))
		(values completed-string t (car pathnames) 1 nil))
	       (t
		(values completed-string nil nil (length pathnames) nil))))
	(:complete
	 (cond ((null pathnames)
		(values so-far nil nil 0 nil))
	       ((null (cdr pathnames))
		(values completed-string t (car pathnames) 1 nil))
	       ((find full-completed-string strings :test #'string-equal)
		(let ((pos (position full-completed-string strings :test #'string-equal)))
		  (values completed-string
			  t (elt pathnames pos) (length pathnames) nil)))
	       (t
		(values completed-string nil nil (length pathnames) nil))))
	(:possibilities
	 (values nil nil nil (length pathnames)
		 (loop with length = (length directory-prefix)
		       for name in pathnames
		       collect (list (subseq (namestring name) length nil)
				     name))))))))

(define-presentation-method accept
    ((type completable-pathname) stream (view textual-view) &key)
  (multiple-value-bind (pathname success string)
      (complete-input stream
		      #'filename-completer
		      :partial-completers '(#\Space)
		      :allow-any-input t)
    (declare (ignore success))
    (or pathname string)))

(define-command com-find-file ()
  (let ((filename (accept 'completable-pathname
			  :prompt "Find File")))
    (with-slots (buffer point syntax) (win *application-frame*)
       (setf buffer (make-instance 'climacs-buffer)
	     point (make-instance 'standard-right-sticky-mark :buffer buffer)
	     syntax (make-instance 'texinfo-syntax :buffer buffer :pane (win *application-frame*))
	     (filename buffer) filename)
       (with-open-file (stream filename :direction :input)
	 (input-from-stream stream buffer 0))
       (beginning-of-buffer point))))

(define-command com-save-buffer ()
  (let ((filename (or (filename (buffer (win *application-frame*)))
		      (accept 'completable-pathname
			      :prompt "Save Buffer to File")))
	(buffer (buffer (win *application-frame*))))
    (with-open-file (stream filename :direction :output :if-exists :supersede)
      (output-to-stream stream buffer 0 (size buffer)))))

(define-command com-beginning-of-buffer ()
  (beginning-of-buffer (point (win *application-frame*))))

(define-command com-end-of-buffer ()
  (end-of-buffer (point (win *application-frame*))))

(define-command com-browse-url ()
  (accept 'url :prompt "Browse URL"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 
;;; Global command table

(make-command-table 'global-climacs-table :errorp nil)

(defun global-set-key (gesture command)
  (add-command-to-command-table command 'global-climacs-table
				:keystroke gesture :errorp nil))

(loop for code from (char-code #\space) to (char-code #\~)
      do (global-set-key (code-char code) 'com-self-insert))

(global-set-key #\newline 'com-self-insert)
(global-set-key #\tab 'com-self-insert)
(global-set-key '(#\f :control) 'com-forward-object)
(global-set-key '(#\b :control) 'com-backward-object)
(global-set-key '(#\a :control) 'com-beginning-of-line)
(global-set-key '(#\e :control) 'com-end-of-line)
(global-set-key '(#\d :control) 'com-delete-object)
(global-set-key '(#\p :control) 'com-previous-line)
(global-set-key '(#\n :control) 'com-next-line)
(global-set-key '(#\o :control) 'com-open-line)
(global-set-key '(#\k :control) 'com-kill-line)
(global-set-key '(#\f :meta) 'com-forward-word)
(global-set-key '(#\b :meta) 'com-backward-word)
(global-set-key '(#\x :meta) 'com-extended-command)
(global-set-key '(#\a :meta) 'com-insert-weird-stuff)
(global-set-key '(#\c :meta) 'com-insert-reversed-string)
(global-set-key '(#\< :shift :meta) 'com-beginning-of-buffer)
(global-set-key '(#\> :shift :meta) 'com-end-of-buffer)
(global-set-key '(#\u :meta) 'com-browse-url)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;; 
;;; C-x command table

(make-command-table 'c-x-climacs-table :errorp nil)

(add-menu-item-to-command-table 'global-climacs-table "C-x"
				:menu 'c-x-climacs-table
				:keystroke '(#\x :control))

(defun c-x-set-key (gesture command)
  (add-command-to-command-table command 'c-x-climacs-table
				:keystroke gesture :errorp nil))

;;; for some reason, C-c does not seem to arrive as far as CLIM.
(c-x-set-key '(#\q :control) 'com-quit)
(c-x-set-key '(#\f :control) 'com-find-file)
(c-x-set-key '(#\s :control) 'com-save-buffer)
