#!/usr/bin/env bb

(ns tracing.strace.pipeline.hierarchy-fold-event
  (:require [clojure.set :as set]
            [clojure.string :as string]
            [clojure.zip :as z]
            [tracing.strace.pipeline.read-depth-first
             :refer
             [get-process-tree-events]]))

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
  [loc event & {:keys [cata-children]
                :or   {cata-children (fn [children _loc] (vec (reverse children)))}}]
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
      #_ (z/edit assoc :path (z/path loc))
      (z/insert-child (set/rename-keys
                        event
                        {:pid       :parent-pid
                         :child-pid :pid})))

    (#{:execve} (:type event))
    (z/insert-child event)

    (#{:exited} (:type event))
    (->
      (z/edit update :children cata-children loc))

    (and
      (#{:exited} (:type event))
      (seq (z/path loc)))
    (z/up)

    #_true
    #_ (doto (as-> state (assert (= (:pid (z/node state)) (:pid event)))))))

(defn build-hierarchy
  [events]
  (loop [loc    (zip {})
         events events
         state  {:depth 1}]
    (let [[head & tail] events]
      (if head
        (recur
          (fold-event loc head)
          tail
          (cond-> state
            (#{:clone} (:type (first events)))
            (update :depth (fnil inc 0))

            (#{:exited} (:type (first events)))
            (update :depth (fnil dec 0))))
        (do
          (when-not (= 0 (:depth state))
            (throw (ex-info "bad input" {:node (z/node loc)
                                         :root (z/root loc)
                                         :events events
                                         :state state})))
          (:children (z/node loc)))))))

(deftest fold-event-clone-execve-test
  (is (match? [{:pid       100
                :child-pid 101
                :type      :clone
                :children  [{:pid        101
                             :parent-pid 100
                             :type       :clone}
                            {:pid       101
                             :child-pid 102
                             :type      :clone
                             :children  [{:parent-pid 101
                                          :pid        102
                                          :type       :clone}]
                             }]}]
        (build-hierarchy
          [{:type :clone :pid 100 :child-pid 101 :ts 0}
           {:type :clone :pid 101 :child-pid 102 :ts 0}
           {:type :exited :pid 102 :ts 0}
           {:type :exited :pid 101 :ts 0}
           {:type :exited :pid 100 :ts 0}])))

  (is (match? [{:pid       100
                :child-pid 101
                :type      :clone
                :children  [{:parent-pid 100
                             :pid        101
                             :type       :clone}
                            {:pid  101
                             :type :execve}]}]
        (build-hierarchy
          [{:type :clone :pid 100 :child-pid 101 :ts 0}
           {:type :execve :pid 101 :ts 0}
           {:type :exited :pid 101 :ts 0}
           {:type :exited :pid 100 :ts 0}])))
  (is (match? [{:pid  100
                :type :execve}
               {:child-pid 101
                :pid       100
                :type      :clone
                :children  [{:parent-pid 100
                             :pid        101
                             :type       :clone}]}]
        (build-hierarchy
          [{:type :execve :pid 100 :ts 0}
           {:type :clone :pid 100 :child-pid 101 :ts 0}
           {:type :exited :pid 101 :ts 0}
           {:type :exited :pid 100 :ts 0}])))
  (is (match? [{:name "first"
                :pid  100
                :type :execve}
               {:name "second"
                :pid  100
                :type :execve}]
        (build-hierarchy
          [{:name "first" :type :execve :pid 100 :ts 0}
           {:name "second" :type :execve :pid 100 :ts 0}
           {:name "exited" :type :exited :pid 100 :ts 0}]))))

(deftest fold-event-duration-test
  (is (match? [{:pid       100
                :ts  1
                :child-pid 101
                :name      "root"
                :type      :clone
                :duration-us 2
                :start-ts 1
                :end-ts 3
                :children [{:pid         101
                            :parent-pid  100
                            :ts 1
                            :start-ts    1
                            :end-ts      2
                            :duration-us 1
                            :name        "root"
                            :type        :clone}]}]
        (build-hierarchy
          [{:ts 1 :type :clone :name "root" :pid 100 :child-pid 101}
           {:ts 2 :type :exited :name "exit child" :pid 101}
           {:ts 3 :type :exited :name "exit root" :pid 100}]) ))
  (is (match? [{:name        "first exec"
                :type        :execve
                :start-ts    1
                :end-ts      2
                :ts 1
                :duration-us 1}
               {:name        "second exec"
                :type        :execve
                :start-ts    2
                :end-ts      5
                :ts 2
                :duration-us 3}]
        (build-hierarchy
          [{:ts 1 :type :execve :name "first exec"}
           {:ts 2 :type :execve :name "second exec"}
           {:ts 5 :type :exited :name "child exited"}]))))

(run-tests)

(build-hierarchy
  (get-process-tree-events
    {:pid                "3012087"
     :file-format-string "/home/me/org/.attach/f6/67fc06-5c41-4525-ae0b-e24b1dd67503/scripts/curlpilot/src/tracing/strace/pipeline/trace-output/trace-output.%s"}))

(into [] [["hi"]
          ["hi"]])

(do
  (defn build-collapsed-stack
    [events]
    (loop [loc    (zip {})
           events events
           state  {:depth 1}]
      (let [[head & tail] events
            cata-children
            (fn [children loc]
              (reverse
                (for [child children]
                  (if (:children child)
                    (assoc child
                      :collapsed-stack
                      (concat (map :collapsed-stack (:children child))))
                    (assoc child
                      :collapsed-stack
                      [(str
                         (string/join
                           ";"
                           (map :name
                             (rest
                               (concat (z/path loc) [(z/node loc) child]))))
                         " "
                         (:duration-us child))])))))]
        (if head
          (recur
            (fold-event loc head :cata-children cata-children)
            tail
            (cond-> state
              (#{:clone} (:type (first events)))
              (update :depth (fnil inc 0))

              (#{:exited} (:type (first events)))
              (update :depth (fnil dec 0))))
          (do
            (when-not (= 0 (:depth state))
              (throw (ex-info "bad input" {:node   (z/node loc)
                                           :root   (z/root loc)
                                           :events events
                                           :state  state})))
            (map :collapsed-stack (:children (z/node loc))))))))
  (build-collapsed-stack
    [{:ts 1 :type :execve :name "root first" :pid 100}
     {:ts 2 :type :execve :name "root second" :pid 100}
     {:ts 3 :type :exited :name "exit 100" :pid 100}])
  (build-collapsed-stack
    [{:ts 1 :type :clone :name "first" :pid 100 :child-pid 101}
     {:ts 2 :type :clone :name "second" :pid 100 :child-pid 102}
     {:ts 3 :type :exited :name "exit 102" :pid 102}
     {:ts 3 :type :exited :name "exit 101" :pid 101}
     {:ts 4 :type :exited :name "exit 100" :pid 100}])
  (build-collapsed-stack
    [{:ts 1 :type :clone :name "first" :pid 100 :child-pid 101}
     {:ts 2 :type :clone :name "second" :pid 101 :child-pid 102}
     {:ts 3 :type :exited :name "exit 102" :pid 102}
     {:ts 3 :type :exited :name "exit 101" :pid 101}
     {:ts 4 :type :exited :name "exit 100" :pid 100}]))
