;;;
;;; Tools to handle the DBF file format
;;;

(in-package :pgloader.db3)

(defclass dbf-connection (fd-connection)
  ((db3 :initarg db3 :accessor fd-db3))
  (:documentation "pgloader connection parameters for DBF files."))

(defmethod initialize-instance :after ((dbfconn dbf-connection) &key)
  "Assign the type slot to dbf."
  (setf (slot-value dbfconn 'type) "dbf"))

(defmethod open-connection ((dbfconn dbf-connection) &key)
  (setf (conn-handle dbfconn)
        (open (fd-path dbfconn)
              :direction :input
              :element-type '(unsigned-byte 8)))
  (let ((db3 (make-instance 'db3:db3)))
    (db3:load-header db3 (conn-handle dbfconn))
    (setf (fd-db3 dbfconn) db3))
  dbfconn)

(defmethod close-connection ((dbfconn dbf-connection))
  (close (conn-handle dbfconn))
  (setf (conn-handle dbfconn) nil
        (fd-db3 dbfconn) nil)
  dbfconn)

(defvar *db3-pgsql-type-mapping*
  '(("C" . "text")			; ignore field-length
    ("N" . "numeric")			; handle both integers and floats
    ("L" . "boolean")			; PostgreSQL compatible representation
    ("D" . "date")			; no TimeZone in DB3 files
    ("M" . "text")))			; not handled yet

(defstruct (db3-field
	     (:constructor make-db3-field (name type length)))
  name type length)

(defmethod format-pgsql-column ((col db3-field))
  "Return a string representing the PostgreSQL column definition."
  (let* ((column-name
	  (apply-identifier-case (db3-field-name col)))
	 (type-definition
	  (cdr (assoc (db3-field-type col)
		      *db3-pgsql-type-mapping*
		      :test #'string=))))
    (format nil "~a ~22t ~a" column-name type-definition)))

(defun list-all-columns (db3 table-name)
  "Return the list of columns for the given DB3-FILE-NAME."
  (list
   (cons table-name
         (loop
            for field in (db3::fields db3)
            collect (make-db3-field (db3::field-name field)
                                    (db3::field-type field)
                                    (db3::field-length field))))))

(declaim (inline logical-to-boolean
		 db3-trim-string
		 db3-date-to-pgsql-date))

(defun logical-to-boolean (value)
  "Convert a DB3 logical value to a PostgreSQL boolean."
  (if (string= value "?") nil value))

(defun db3-trim-string (value)
  "DB3 Strings a right padded with spaces, fix that."
  (string-right-trim '(#\Space) value))

(defun db3-date-to-pgsql-date (value)
  "Convert a DB3 date to a PostgreSQL date."
  (let ((year  (subseq value 0 4))
	(month (subseq value 4 6))
	(day   (subseq value 6 8)))
    (format nil "~a-~a-~a" year month day)))

(defun list-transforms (db3)
  "Return the list of transforms to apply to each row of data in order to
   convert values to PostgreSQL format"
  (loop
     for field in (db3::fields db3)
     for type = (db3::field-type field)
     collect
       (cond ((string= type "L") #'logical-to-boolean)
             ((string= type "C") #'db3-trim-string)
             ((string= type "D") #'db3-date-to-pgsql-date)
             (t                  nil))))
