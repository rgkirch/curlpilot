(ns tracing.strace.pipeline.read-depth-first
  (:require [clojure.java.io :as io]
            [clojure.string :as str])
  (:import [java.io BufferedReader]))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Regex Definitions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(def ^:private pid_re "([0-9]+)")
(def ^:private comm_re "<([^>]+)>")
(def ^:private timestamp_re "([0-9]+\\.[0-9]+)")
(def ^:private args_re "(.*)")

;; Matches clone(...) = 2732203<bash>
(def ^:private clone_re
  (re-pattern (str "^" pid_re comm_re " +" timestamp_re " clone\\(" args_re "\\) = " pid_re comm_re "$")))

;; Matches syscalls like execve(...) = 0
(def ^:private execve_re
  (re-pattern (str "^" pid_re comm_re " +" timestamp_re " execve\\(" args_re "\\) = (0)$")))

;; +++ exited with 1 +++
(def ^:private exited_re
  (re-pattern (str "^" pid_re comm_re " +" timestamp_re " \\+\\+\\+ exited with ([0-9]+) \\+\\+\\+$")))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Parsing Helper Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defn- parse-clone
  "Takes a regex match for clone_re and returns a structured map."
  [match]
  (let [[_ p-pid p-comm ts args c-pid c-comm] match]
    {:type       :clone
     :pid        (Integer/parseInt p-pid)
     :comm       p-comm
     :ts         (Double/parseDouble ts)
     :args       args
     :child-pid  (Integer/parseInt c-pid)
     :child-comm c-comm}))

(defn- parse-execve
  "Takes a regex match for execve_re and returns a structured map."
  [match]
  (let [[_ pid comm ts args ret] match]
    {:type   :execve
     :pid    (Integer/parseInt pid)
     :comm   comm
     :ts     (Double/parseDouble ts)
     :args   args
     :return (Integer/parseInt ret)}))

(defn- parse-exited
  "Takes a regex match for exited_re and returns a structured map."
  [match]
  (let [[_ pid comm ts exit-code] match]
    {:type      :exited
     :pid       (Integer/parseInt pid)
     :comm      comm
     :ts        (Double/parseDouble ts)
     :exit-code (Integer/parseInt exit-code)}))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Core Lazy-Seq Traversal Logic
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Forward-declare the main public function so it can be called recursively
;; by the helper functions.
(declare get-process-tree-events)

(defn- parse-line-and-recurse
  "Parses a single line and returns a lazy-seq of events.
   - file-format-string: Passed through for recursive calls.
   - line: The string line to parse.
   - rest-of-lines-fn: A 0-arg function (thunk) that, when called,
     will lazily continue processing the *rest of the current file*."
  [file-format-string line rest-of-lines-fn]
  (let [clone-match  (re-find clone_re line)
        execve-match (re-find execve_re line)
        exited-match (re-find exited_re line)]
    (cond
      ;; --- Case 1: clone (Depth-First Traversal) ---
      ;; This is the core logic.
      clone-match
      (let [clone-event (parse-clone clone-match)
            child-pid   (:child-pid clone-event)

            ;; 1. Lazily get the *entire* event sequence for the new child process.
            child-seq (get-process-tree-events {:pid child-pid :file-format-string file-format-string})

            ;; 2. Get the lazy sequence for the *rest of the parent's file*.
            parent-rest-seq (rest-of-lines-fn)]

        ;; 3. Emit the clone event, then lazily concatenate the *entire*
        ;;    child sequence, and *then* lazily concatenate the rest
        ;;    of the parent's sequence.
        (cons clone-event (lazy-cat child-seq parent-rest-seq)))

      ;; --- Case 2: execve ---
      ;; Emit the event and lazily continue with the rest of the *same* file.
      execve-match
      (cons (parse-execve execve-match) (rest-of-lines-fn))

      ;; --- Case 3: exited ---
      ;; Emit the event and lazily continue with the rest of the *same* file.
      exited-match
      (cons (parse-exited exited-match) (rest-of-lines-fn))

      ;; --- Case 4: No Match ---
      ;; Skip this line and lazily continue with the rest of the *same* file.
      :else
      (rest-of-lines-fn))))

(defn- lazy-read-lines
  "Returns a lazy-seq of parsed events from a BufferedReader.
   Manages the reader's lifecycle, closing it on EOF."
  [^BufferedReader rdr file-format-string]
  (lazy-seq
    (if-let [line (.readLine rdr)]
      ;; Line exists: process it.
      ;; Pass a thunk that will recursively call this function
      ;; to process the *next* line when the consumer requests it.
      (parse-line-and-recurse file-format-string line
                              #(lazy-read-lines rdr file-format-string))
      ;; EOF: Close the reader and return nil to terminate the lazy-seq.
      (do (.close rdr)
          nil))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public API
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defn get-process-tree-events
  "Lazily parses strace logs for a process and all its children,
   following clone() calls in a depth-first traversal.

   - root-map: A map containing the root :pid, e.g. {:pid 12345}
   - file-format-string: A format string for pid filenames,
     e.g. \"/tmp/strace-%s.log\"

   Returns a single, flat, lazy sequence of event maps."
  [{:keys [pid file-format-string]}]
  (let [filename (format file-format-string pid)]
    (try
      (let [rdr (io/reader filename)]
        ;; Kick off the lazy reading process.
        ;; The lazy-seq returned by lazy-read-lines will manage
        ;; closing the reader.
        (lazy-read-lines rdr file-format-string))

      (catch java.io.FileNotFoundException _
        ;; If a log file doesn't exist (e.g., for a child),
        ;; just return an empty sequence for that branch.
        (println (str "Warning: Log file not found, skipping: " filename))
        '())

      (catch Exception e
        ;; Handle other potential I/O errors
        (println (str "Error processing file: " filename " - " (.getMessage e)))
        (do
          (.printStackTrace e)
          '())))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Example Usage
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(comment

  ;; Create dummy files for testing:

  ;; File for root PID 100
  (spit "/tmp/strace-100.log"
        (str/join \newline
                  ["100<main>   1.000000 execve(\"cmd1\", [], []) = 0"
                   "100<main>   1.100000 clone(args...) = 200<child1>"
                   "100<main>   1.300000 +++ exited with 0 +++"]))

  ;; File for child PID 200
  (spit "/tmp/strace-200.log"
        (str/join \newline
                  ["200<child1> 1.150000 execve(\"child-cmd\", [], []) = 0"
                   "200<child1> 1.200000 clone(args...) = 300<grandchild>"
                   "200<child1> 1.250000 +++ exited with 1 +++"]))

  ;; File for grandchild PID 300
  (spit "/tmp/strace-300.log"
        (str/join \newline
                  ["300<grandchild> 1.220000 execve(\"grandchild-cmd\", [], []) = 0"
                   "300<grandchild> 1.230000 +++ exited with 0 +++"]))


  ;; --- Run the parser ---

  (let [all-events (get-process-tree-events {:pid 100 :file-format-string "/tmp/strace-%s.log"})]

    ;; The sequence is lazy, so `all-events` is just a seq object.
    (println "--- Type of result (should be lazy): ---")
    (println (type all-events))

    ;; Force realization by converting to a vector
    (println "\n--- Realized Events (Depth-First Order): ---")
    (clojure.pprint/pprint (vec all-events)))

  ;; Expected Output:
  ;;
  ;; --- Type of result (should be lazy): ---
  ;; clojure.lang.LazySeq
  ;;
  ;; --- Realized Events (Depth-First Order): ---
  ;; [{:type :execve,
  ;;   :pid 100,
  ;;   :comm "main",
  ;;   :ts 1.0,
  ;;   :args "\"cmd1\", [], []",
  ;;   :return 0}
  ;;  {:type :clone,                           ; <-- 1. Parent clones
  ;;   :pid 100,
  ;;   :comm "main",
  ;;   :ts 1.1,
  ;;   :args "args...",
  ;;   :child-pid 200,
  ;;   :child-comm "child1"}
  ;;  {:type :execve,                          ; <-- 2. Child starts
  ;;   :pid 200,
  ;;   :comm "child1",
  ;;   :ts 1.15,
  ;;   :args "\"child-cmd\", [], []",
  ;;   :return 0}
  ;;  {:type :clone,                           ; <-- 3. Child clones
  ;;   :pid 200,
  ;;   :comm "child1",
  ;;   :ts 1.2,
  ;;   :args "args...",
  ;;   :child-pid 300,
  ;;   :child-comm "grandchild"}
  ;;  {:type :execve,                          ; <-- 4. Grandchild starts
  ;;   :pid 300,
  ;;   :comm "grandchild",
  ;;   :ts 1.22,
  ;;   :args "\"grandchild-cmd\", [], []",
  ;;   :return 0}
  ;;  {:type :exited,                          ; <-- 5. Grandchild exits
  ;;   :pid 300,
  ;;   :comm "grandchild",
  ;;   :ts 1.23,
  ;;   :exit-code 0}
  ;;  {:type :exited,                          ; <-- 6. Child exits
  ;;   :pid 200,
  ;;   :comm "child1",
  ;;   :ts 1.25,
  ;;   :exit-code 1}
  ;;  {:type :exited,                          ; <-- 7. Parent resumes and exits
  ;;   :pid 100,
  ;;   :comm "main",
  ;;   :ts 1.3,
  ;;   :exit-code 0}]

  )
