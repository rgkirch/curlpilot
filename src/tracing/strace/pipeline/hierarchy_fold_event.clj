#!/usr/bin/env bb

(ns tracing.strace.pipeline.hierarchy-fold-event
  (:require [clojure.set :as set]
            [clojure.zip :as z]
            [tracing.strace.pipeline.read-depth-first :refer [get-process-tree-events]]))

(require '[clojure.zip :as z])
(require '[clojure.test :refer [run-tests deftest is]])
(require '[matcher-combinators.test])
(require '[debux.core :refer [dbg dbgn]])

(defn terminate-duration
  [{start-ts :ts :as state} end-ts]
  (try
    (assoc state
      :start-ts start-ts
      :end-ts end-ts
      :duration-us (- end-ts start-ts))
    (catch Exception _
      (throw
        (ex-info
          "failed to compute duration"
          {:state state :end-ts end-ts})))))

(defn zip
  [state]
  (z/zipper
    (constantly true)
    :children
    (fn [node chldn]
      (assoc node :children chldn))
    state))

(defn fold-event
  [loc event]
  (cond-> loc
    (and
      (#{:clone :execve :exited} (:type event))
      (seq (z/children loc)))
    (->
      (z/down)
      (z/edit terminate-duration (:ts event))
      (z/up))

    (#{:clone} (:type event))
    (->
      (z/insert-child event)
      (z/down)
      #_(z/edit assoc :path (z/path loc)))

    (#{:clone} (:type event))
    (z/insert-child (set/rename-keys
                      event
                      {:pid       :parent-pid
                       :child-pid :pid}))

    (#{:execve} (:type event))
    (z/insert-child event)

    (#{:exited} (:type event))
    (->
      (z/edit update :children (comp vec reverse))
      (z/up))

    #_true
    #_ (doto (as-> state (assert (= (:pid (z/node state)) (:pid event)))))))

(defn run-fold
  [root-pid]
  ())

#_(map z/root
    (reductions
      fold-event (zip {})
      [{:type :clone :pid 100 :child-pid 101 :ts 0}
       {:type :clone :pid 101 :child-pid 102 :ts 0}
       {:type :exited :pid 102 :ts 0}
       {:type :exited :pid 101 :ts 0}]))

(defn fold-events
  ([events]
   (fold-events (zip {}) events))
  ([loc events]
   (reduce fold-event loc events)))

(defn reduce-events
  [events]
  (update (z/root (fold-events events))
    :children (comp vec reverse)))

(deftest fold-event-clone-execve-test
  (is (match? {:children
               [{:child-pid 101
                 :pid       100
                 :type      :clone
                 :children [{:parent-pid 100
                              :pid        101
                              :type       :clone}
                             {:child-pid 102
                              :children  [{:parent-pid 101
                                           :pid        102
                                           :type       :clone}]
                              :pid       101
                              :type      :clone}]}]}
        (reduce-events
          [{:type :clone :pid 100 :child-pid 101 :ts 0}
           {:type :clone :pid 101 :child-pid 102 :ts 0}
           {:type :exited :pid 102 :ts 0}
           {:type :exited :pid 101 :ts 0}])))

  (is (match? {:children
               [{:pid       100
                 :child-pid 101
                 :type      :clone
                 :children [{:parent-pid 100
                              :pid        101
                              :type       :clone}
                             {:pid  101
                              :type :execve}]}]}
        (reduce-events
          [{:type :clone :pid 100 :child-pid 101 :ts 0}
           {:type :execve :pid 101 :ts 0}
           {:type :exited :pid 101 :ts 0}])))
  (is (match? {:children [{:pid  100
                           :type :execve}
                          {:child-pid 101
                           :pid       100
                           :type      :clone
                           :children [{:parent-pid 100
                                        :pid        101
                                        :type       :clone}]}]}
        (reduce-events
          [{:type :execve :pid 100 :ts 0}
           {:type :clone :pid 100 :child-pid 101 :ts 0}
           {:type :exited :pid 101 :ts 0}])))
  (is (match? {:children [{:name "first"
                           :pid  100
                           :type :execve}
                          {:name "second"
                           :pid  100
                           :type :execve}]}
        (reduce-events
          [{:name "first" :type :execve :pid 100 :ts 0}
           {:name "second" :type :execve :pid 100 :ts 0}]))))

(z/up
  (reduce
    fold-event
    (zip {})
    [{:ts 1 :type :clone :name :clone :pid 100 :child-pid 101}
     {:ts 2 :type :exited :name "exit clone" :pid 101}
     #_{:ts 3 :type :exited :name "exit root" :pid 100}]))

(deftest fold-event-duration-test
  (is (match? {:children
               [{:child-pid 101
                 :name      "root"
                 :pid       100
                 :ts  1
                 :type      :clone
                 :children [{:duration-us 1
                             :end-ts      2
                             :name        "root"
                             :parent-pid  100
                             :pid         101
                             :start-ts    1
                             :type        :clone}]}]}
        (reduce-events
          [{:ts 1 :type :clone  :name :clone      :pid 100 :child-pid 101}
           {:ts 2   :type :exited :name "exit clone" :pid 101}
           {:ts 3   :type :exited :name "exit root" :pid 100}])))
  (is (match? {:children
               [{:name        "root"
                 :type        :clone
                 :start-us    1
                 :end-us      2
                 :duration-us 1}]}
        (reduce-events
          [{:ts 1 :type :execve :name "first exec"}
           {:ts 2 :type :execve :name "second exec"}
           {:ts 5 :type :exited :name "child exited"}]))))

(reduce-events
  [{:ts 1 :type :execve :name "root" :pid 100}])

(reduce-events
  [{:ts 1 :type :clone :name "root" :pid 100 :child-pid 101}
   {:ts 2 :type :exited :name "exit root" :pid 100}])

(run-tests)

(reduce-events
  (butlast
    (get-process-tree-events
      {:pid                "3012087"
       :file-format-string "/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/src/tracing/strace/pipeline/trace-output/trace-output.%s"})))
