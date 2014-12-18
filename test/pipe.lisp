(in-package :cl-async-test)
(in-suite cl-async-test-core)

;; FIXME: use mkdtemp
;; FIXME: that's currently mostly copy&paste from tcp tests
;; FIXME: no-overlap should be ported, too

(test pipe-simple-client-server
  "Test both pipe-connect and pipe-server"
  (multiple-value-bind (server-reqs server-data connect-num client-replies client-data)
      (async-let ((server-reqs 0)
                  (server-data "")
                  (connect-num 0)
                  (client-replies 0)
                  (client-data ""))
        (test-timeout 3)

        (as:pipe-server "/tmp/blabla"
          (lambda (sock data)
            (incf server-reqs)
            (setf server-data (concat server-data (babel:octets-to-string data)))
            (as:write-socket-data sock "thxlol "))
          nil
          :connect-cb (lambda (sock)
                        (declare (ignore sock))
                        (incf connect-num)))

        (loop repeat 2
              ;; split request "hai " up between pipe-connect and write-socket-data
              do (let ((sock (as:pipe-connect
                              "/tmp/blabla"
                              (lambda (sock data)
                                (incf client-replies)
                                (unless (as:socket-closed-p sock)
                                  (as:close-socket sock))
                                (setf client-data (concat client-data (babel:octets-to-string data))))
                              (lambda (ev)
                                (error ev))
                              :data "ha")))
                   (as:write-socket-data sock "i ")))

        (as:delay (lambda () (as:exit-event-loop))
                  :time 1))
    (is (= server-reqs 2) "number of server requests")
    (is (string= server-data "hai hai ") "received server data")
    (is (= connect-num 2) "number of connections (from connect-cb)")
    (is (= client-replies 2) "number of replies sent to client")
    (is (string= client-data "thxlol thxlol ") "received client data")))

(test pipe-connect-fail
  "Make sure a pipe connection fails"
  (let ((num-err 0))
    (signals as:pipe-not-found
      (async-let ()
        (test-timeout 2)
        (as:pipe-connect "/tmp/nosuchpipe"
          (lambda (sock data) (declare (ignore sock data)))
          (lambda (ev)
            (incf num-err)
            (error ev))
          :data "hai"
          :read-timeout 1)))
    (is (= num-err 1))))

(test pipe-server-close
  "Make sure a pipe-server closes gracefully"
  (multiple-value-bind (closedp)
      (async-let ((closedp nil))
        (test-timeout 3)
        (let* ((server (as:pipe-server "/tmp/blabla"
                         (lambda (sock data) (declare (ignore sock data)))
                         (lambda (ev) (declare (ignore ev))))))
          (assert server () "failed to listen at port 41818")
          (as:pipe-connect "/tmp/blabla"
            (lambda (sock data) (declare (ignore sock data)))
            (lambda (ev) (declare (ignore ev)))
            :connect-cb
              (lambda (sock)
                (as:delay
                  (lambda ()
                    (let ((closed-pre (as::socket-server-closed server)))
                      (as:close-socket sock)
                      (as:delay
                        (lambda ()
                          (setf closedp (and closed-pre
                                             (as::socket-server-closed server)))))))
                  :time 1)))
          (as:delay (lambda () (as:close-socket-server server)) :time .1)))
    (is-true closedp)))

(test pipe-server-stream
  "Make sure a pipe-server stream functions properly"
  (multiple-value-bind (server-data)
      (async-let ((server-data nil))
        (test-timeout 3)
        (as:pipe-server "/tmp/blabla"
          (lambda (sock stream)
            (let ((buff (make-array 1024 :element-type '(unsigned-byte 8))))
              (loop for n = (read-sequence buff stream)
                    while (< 0 n) do
                (setf server-data (concat server-data (babel:octets-to-string (subseq buff 0 n))))))
            (as:close-socket sock)
            (as:exit-event-loop))
          (lambda (ev) (declare (ignore ev)))
          :stream t)
        (as:pipe-connect "/tmp/blabla"
          (lambda (sock data) (declare (ignore sock data)))
          (lambda (ev) (declare (ignore ev)))
          :data "HELLO!"))
    (is (string= server-data "HELLO!"))))
