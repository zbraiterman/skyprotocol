;;; -*- Gerbil -*-
(import :tcpubsub/pubsub/lib
        :std/logger ; logger
        :std/sugar
        :std/cli/getopt ; cli options
        :std/io ; socket stuff and other
        :std/iter ; for*
        :std/misc/evector ; evector
        :std/net/address) ; resolve-address

(export main)

(deflogger pubsub)

(def (main . args)
  (call-with-getopt pubsub-main args
    program: "pubsub"
    help: "Simple tcp pubsub peer"
    (argument 'laddr help: "local address")))

(def (pubsub-main opt)
  (start-logger! (current-output-port))
  (current-logger-options 5)
  (run (hash-get opt 'laddr)))

(def (run addr)
  (let* ((laddr (resolve-address addr))
         (sock (tcp-listen laddr))
         (messages (make-evector #(#f) 0)) ; shared message buffer
         (messages-mx (make-mutex))
         (nodes (make-evector #(#f) 0)) ; shared node buffer
         (nodes-mx (make-mutex)))
    (debugf "Starting node on: ~a" laddr)
    (while #t
      (try
        (using ((client (ServerSocket-accept sock) : StreamSocket)
                (node (create-node client) : Node))
          (when client
            (debugf "Accepted connection from: ~a, with id: ~a" (node.sock.peer-address) node.id)
            (with-lock nodes-mx (lambda () 
              (evector-push! nodes node)))
            (spawn command-reader node messages messages-mx nodes nodes-mx)))
        (catch (e)
          (errorf "Error accepting connection: ~a" e))))))

(def (command-reader (node : Node) messages messages-mx nodes nodes-mx)
  (debugf "Spawned new command-reader for node: ~a" node.id)
  (try
    (while #t
      ;; Wait for the next command
      (let (cm (read-command node.reader))
        (match cm
          ;; SYNC command
          ((Command 0 _)
            (debugf "Received SYNC command from: ~a" node.id)
            (spawn send-messages messages-mx messages node.writer))
          ;; POST command
          ;; TODO resend POST to other nodes
          ((Command 1 m)
            (debugf "Received POST command from: ~a" node.id)
            (with-lock messages-mx (lambda () 
              (debugf "Saving new message: ~a" (bytes->string m))
              (evector-push! messages m))))
          ;; ADD-PEER command
          ((Command 2 m)
            (debugf "Received ADD-PEER command from: ~a" node.id)
            (try 
              (using ((node-sock (tcp-connect (resolve-address (bytes->string m))) : StreamSocket)
                      (new-node (create-node node-sock) : Node))
                (write-command/try (sync) new-node.writer)
                (debugf "Sent sync command to the node: ~a" new-node.id)
                (with-lock nodes-mx (lambda () 
                  (debugf "Added new node to the internal list of nodes")
                  (evector-push! nodes new-node)))
                (spawn command-reader new-node messages messages-mx nodes nodes-mx))
              (catch (e)
                (errorf "Cannot add peer: ~a" e))))
          ((Command c m)
            (errorf "Received incorrect command: (Command ~a ~a)" c m)))))
    (catch (e)
      (errorf "Cannot read command: ~a" e)
      (debugf "Closing connection with node: ~a" node.id)
      (node.sock.close))))

(def (send-messages mx evec (writer : BufferedWriter))
  (for* ((i (in-range (evector-fill-pointer evec))))
      (let ((el (with-lock mx (lambda () (evector-ref evec i)))))
        (debugf "Sending message: ~a" (bytes->string el))
        (write-command/try (post el) writer))))
