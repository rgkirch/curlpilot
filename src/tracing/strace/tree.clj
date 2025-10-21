#!/usr/bin/env bb

(require '[cheshire.core :as json]
         '[clojure.java.io :as io])

(defn build-process-map
  "Reads JSON lines from *in* and builds a map of pid -> process-data."
  []
  (with-open [rdr (io/reader *in*)]
    (->> (line-seq rdr)
         (map #(json/parse-string % :key-fn keyword))
         ;; Key the entire map by PID for easy lookup
         (reduce (fn [acc proc] (assoc acc (:pid proc) proc))
                 {}))))

(declare print-node) ;; Declare for mutual recursion

(defn print-children [proc-map children-map parent-pid indent-str]
  "Helper function to print all children of a given parent"
  (let [children (get children-map parent-pid)
        new-indent (str indent-str "  ")]
    (doseq [child children]
      ;; 'child' is the full process map { :pid ... }
      (print-node proc-map children-map child new-indent))))

(defn print-node [proc-map children-map node indent-str]
  "Recursively prints a process node and its children."
  ;; 1. Print the current node
  (println (str indent-str "+-- " (:cmd node)
                " (pid: " (:pid node)
                ", dur: " (format "%.4f" (:total_dur node)) "s"
                (if (= 1 (:had_execve node)) "" " <no-execve>")))

  ;; 2. Find and recurse for children
  (print-children proc-map children-map (:pid node) (str indent-str "    ")))

;; --- Main Execution ---

(let [proc-map (build-process-map)
      ;; Create a map of {ppid -> [list of child-processes]}
      children-map (group-by :ppid (vals proc-map))]

  (println "Process Tree (Forest):")

  ;; Get all "root" nodes (processes where ppid is nil)
  ;; This will print a "forest" if there are multiple top-level processes.
  (let [root-nodes (get children-map nil)]
    (doseq [root root-nodes]
      (print-node proc-map children-map root ""))))
