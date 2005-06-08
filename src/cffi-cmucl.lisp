;;;; -*- Mode: lisp; indent-tabs-mode: nil -*-
;;;
;;; cffi-sbcl.lisp --- CFFI-SYS implementation for CMU CL.
;;;
;;; Copyright (C) 2005, James Bielman  <jamesjb@jamesjb.com>
;;;
;;; Permission is hereby granted, free of charge, to any person
;;; obtaining a copy of this software and associated documentation
;;; files (the "Software"), to deal in the Software without
;;; restriction, including without limitation the rights to use, copy,
;;; modify, merge, publish, distribute, sublicense, and/or sell copies
;;; of the Software, and to permit persons to whom the Software is
;;; furnished to do so, subject to the following conditions:
;;;
;;; The above copyright notice and this permission notice shall be
;;; included in all copies or substantial portions of the Software.
;;;
;;; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
;;; EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
;;; MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
;;; NONINFRINGEMENT.  IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
;;; HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
;;; WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
;;; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
;;; DEALINGS IN THE SOFTWARE.
;;;

;;;# Administrivia

(defpackage #:cffi-sys
  (:use #:common-lisp #:alien #:c-call)
  (:export
   #:pointerp
   #:null-ptr
   #:null-ptr-p
   #:foreign-alloc
   #:foreign-free
   #:with-foreign-ptr
   #:%foreign-funcall
   #:%foreign-type-alignment
   #:%foreign-type-size
   #:%load-foreign-library
   #:%mem-ref))

(in-package #:cffi-sys)

;;;# Basic Pointer Operations

(declaim (inline pointerp))
(defun pointerp (ptr)
  "Return true if PTR is a foreign pointer."
  (sys:system-area-pointer-p ptr))

(declaim (inline null-ptr))
(defun null-ptr ()
  "Construct and return a null pointer."
  (sys:int-sap 0))

(declaim (inline null-ptr-p))
(defun null-ptr-p (ptr)
  "Return true if PTR is a null pointer."
  (zerop (sys:sap-int ptr)))

(defmacro with-foreign-ptr ((var size &optional size-var) &body body)
  "Bind VAR to SIZE bytes of foreign memory during BODY.  The
pointer in VAR is invalid beyond the dynamic extent of BODY, and
may be stack-allocated if supported by the implementation.  If
SIZE-VAR is supplied, it will be bound to SIZE during BODY."
  (unless size-var
    (setf size-var (gensym "SIZE")))
  ;; If the size is constant we can stack-allocate.
  (if (constantp size)
      (let ((alien-var (gensym "ALIEN")))
        `(with-alien ((,alien-var (array (unsigned 8) ,(eval size))))
           (let ((,size-var ,size)
                 (,var (alien-sap ,alien-var)))
             (declare (ignorable ,size-var))
             ,@body)))
      `(let* ((,size-var ,size)
              (,var (foreign-alloc ,size-var)))
         (declare (ignorable ,size-var))
         (unwind-protect
              (progn ,@body)
           (foreign-free ,var)))))

;;;# Allocation
;;;
;;; Functions and macros for allocating foreign memory on the stack
;;; and on the heap.  The main CFFI package defines macros that wrap
;;; FOREIGN-ALLOC and FOREIGN-FREE in UNWIND-PROTECT for the common usage
;;; when the memory has dynamic extent.

(defun foreign-alloc (size)
  "Allocate SIZE bytes on the heap and return a pointer."
  (declare (type (unsigned-byte 32) size))
  (alien-funcall
   (extern-alien
    "malloc"
    (function system-area-pointer unsigned))
   size))

(defun foreign-free (ptr)
  "Free a PTR allocated by FOREIGN-ALLOC."
  (declare (type system-area-pointer ptr))
  (alien-funcall
   (extern-alien
    "free"
    (function (values) system-area-pointer))
   ptr))

;;;# Dereferencing

(defun %mem-ref (ptr type &optional (offset 0))
  "Dereference an object of TYPE at OFFSET bytes from PTR."
  (ecase type
    (:char (sys:signed-sap-ref-8 ptr offset))
    (:unsigned-char (sys:sap-ref-8 ptr offset))
    (:short (sys:signed-sap-ref-16 ptr offset))
    (:unsigned-short (sys:sap-ref-16 ptr offset))
    (:int (sys:signed-sap-ref-32 ptr offset))
    (:unsigned-int (sys:sap-ref-32 ptr offset))
    (:long (sys:signed-sap-ref-32 ptr offset))
    (:unsigned-long (sys:sap-ref-32 ptr offset))
    (:float (sys:sap-ref-single ptr offset))
    (:double (sys:sap-ref-double ptr offset))
    (:pointer (sys:sap-ref-sap ptr offset))))

(define-compiler-macro %mem-ref (&whole form ptr type &optional (offset 0))
  "Compiler macro to open-code when TYPE is constant."
  (if (constantp type)
      (progn
        #-(and) (format t "~&;; Open-coding %MEM-REF form: ~S~%" form)
        (ecase (eval type)
          (:char `(sys:signed-sap-ref-8 ,ptr ,offset))
          (:unsigned-char `(sys:sap-ref-8 ,ptr ,offset))
          (:short `(sys:signed-sap-ref-16 ,ptr ,offset))
          (:unsigned-short `(sys:sap-ref-16 ,ptr ,offset))
          (:int `(sys:signed-sap-ref-32 ,ptr ,offset))
          (:unsigned-int `(sys:sap-ref-32 ,ptr ,offset))
          (:long `(sys:signed-sap-ref-32 ,ptr ,offset))
          (:unsigned-long `(sys:sap-ref-32 ,ptr ,offset))
          (:float `(sys:sap-ref-single ,ptr ,offset))
          (:double `(sys:sap-ref-double ,ptr ,offset))
          (:pointer `(sys:sap-ref-sap ,ptr ,offset))))
      form))

(defun %mem-set (value ptr type &optional (offset 0))
  "Dereference an object of TYPE at OFFSET bytes from PTR."
  (ecase type
    (:char (setf (sys:signed-sap-ref-8 ptr offset) value))
    (:unsigned-char (setf (sys:sap-ref-8 ptr offset) value))
    (:short (setf (sys:signed-sap-ref-16 ptr offset) value))
    (:unsigned-short (setf (sys:sap-ref-16 ptr offset) value))
    (:int (setf (sys:signed-sap-ref-32 ptr offset) value))
    (:unsigned-int (setf (sys:sap-ref-32 ptr offset) value))
    (:long (setf (sys:signed-sap-ref-32 ptr offset) value))
    (:unsigned-long (setf (sys:sap-ref-32 ptr offset) value))
    (:float (setf (sys:sap-ref-single ptr offset) value))
    (:double (setf (sys:sap-ref-double ptr offset) value))
    (:pointer (setf (sys:sap-ref-sap ptr offset) value))))

(define-setf-expander %mem-ref (ptr type &optional (offset 0))
  "SETF expander for %MEM-REF that doesn't rebind TYPE.
This is necessary for the compiler macro on %MEM-SET to be able
to open-code (SETF %MEM-REF) forms."
  (multiple-value-bind (dummies vals newval setter getter)
      (get-setf-expansion ptr)
    (declare (ignore setter newval))
    (let ((store (gensym)))
      (values
       dummies
       vals
       `(,store)
       `(progn
          (%mem-set ,store ,getter ,type ,offset)
          ,store)
       `(%mem-ref ,getter)))))

(define-compiler-macro %mem-set (&whole form value ptr type &optional (offset 0))
  "Compiler macro to open-code when TYPE is constant."
  (if (constantp type)
      (progn
        #-(and) (format t "~&;; Open-coding (SETF %MEM-REF) form: ~S~%" form)
        (ecase (eval type)
          (:char `(setf (sys:signed-sap-ref-8 ,ptr ,offset) ,value))
          (:unsigned-char `(setf (sys:sap-ref-8 ,ptr ,offset) ,value))
          (:short `(setf (sys:signed-sap-ref-16 ,ptr ,offset) ,value))
          (:unsigned-short `(setf (sys:sap-ref-16 ,ptr ,offset) ,value))
          (:int `(setf (sys:signed-sap-ref-32 ,ptr ,offset) ,value))
          (:unsigned-int `(setf (sys:sap-ref-32 ,ptr ,offset) ,value))
          (:long `(setf (sys:signed-sap-ref-32 ,ptr ,offset) ,value))
          (:unsigned-long `(setf (sys:sap-ref-32 ,ptr ,offset) ,value))
          (:float `(setf (sys:sap-ref-single ,ptr ,offset) ,value))
          (:double `(setf (sys:sap-ref-double ,ptr ,offset) ,value))
          (:pointer `(setf (sys:sap-ref-sap ,ptr ,offset) ,value))))
      form))

;;;# Calling Foreign Functions

(defun convert-foreign-type (type-keyword)
  "Convert a CFFI type keyword to an ALIEN type."
  (ecase type-keyword
    (:char             'char)
    (:unsigned-char    'unsigned-char)
    (:short            'short)
    (:unsigned-short   'unsigned-short)
    (:int              'int)
    (:unsigned-int     'unsigned-int)
    (:long             'long)
    (:unsigned-long    'unsigned-long)
    (:float            'single-float)
    (:double           'double-float)
    (:pointer          'system-area-pointer)
    (:void             'void)))

(defun %foreign-type-size (type-keyword)
  "Return the size in bytes of a foreign type."
  (/ (alien-internals:alien-type-bits
      (alien-internals:parse-alien-type
       (convert-foreign-type type-keyword))) 8))

(defun %foreign-type-alignment (type-keyword)
  "Return the alignment in bytes of a foreign type."
  (/ (alien-internals:alien-type-alignment
      (alien-internals:parse-alien-type
       (convert-foreign-type type-keyword))) 8))

(defun foreign-funcall-type-and-args (args)
  "Return an ALIEN function type for ARGS."
  (let ((return-type nil))
    (loop for (type arg) on args by #'cddr
       if arg collect (convert-foreign-type type) into types
          and collect arg into fargs
       else do (setf return-type (convert-foreign-type type))
       finally (return (values types fargs return-type)))))

(defmacro %%foreign-funcall (name types fargs rettype)
  "Internal guts of %FOREIGN-FUNCALL."
  `(alien-funcall
    (extern-alien ,name (function ,rettype ,@types))
    ,@fargs))

(defmacro %foreign-funcall (name &rest args)
  "Perform a foreign function call, document it more later."
  (multiple-value-bind (types fargs rettype)
      (foreign-funcall-type-and-args args)
    `(%%foreign-funcall ,name ,types ,fargs ,rettype)))

;;;# Loading Foreign Libraries

(defun %load-foreign-library (name)
  "Load the foreign library NAME."
  (load-foreign name))