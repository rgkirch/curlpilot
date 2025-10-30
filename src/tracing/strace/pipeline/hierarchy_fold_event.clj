#!/usr/bin/env bb

(ns user)

(require '[clojure.zip :as z])
(require '[clojure.test :refer [run-tests deftest is]])

(do
  (defn fold-event [state event]
    (cond
      (nil? (z/node state))
      (z/replace state event)

      (= "clone" (:type event))
      (-> state
        (z/insert-child event)
        (z/down))

      (and
        (= "execve" (:type event))
        (= "clone" (:type (z/node state))))
      (-> state
        (z/insert-child event)
        (z/down))

      (and
        (= "execve" (:type event))
        (= "execve" (:type (z/node state))))
      (-> state
        (z/up)
        (z/insert-child event)
        (z/down))

      (= "execve" (:type event))
      (-> state
        (z/up)
        (z/insert-child event)
        (z/down))

      (= "exited" (:type event))
      (-> state
        (doto (as-> state (assert (= (:pid (z/node state)) (:pid event)))))
        (cond-> (= "execve" (:type (z/node state))) (z/up))
        (z/edit merge (select-keys event ["end_us" "exit_code"]))
        (z/edit (fn [m] (assoc m :duration_us (- (:end_us m) (:start_us m)))))
        (z/up))))

  (let [state (-> (z/zipper
                    (constantly true)
                    :children
                    (fn [node chldn]
                      (assoc node :children chldn))
                    nil)
                (fold-event {:type "clone" :name "root" :pid 100 :child-pid 101})
                (fold-event {:type "execve" :name "root exec" :pid 101})
                (fold-event {:type "clone" :name "child" :pid 101 :child-pid 102}))
        path  (z/path state)]
    path))

(deftest fold-event-test
  (let [state (z/zipper
                (constantly true)
                :children
                (fn [node chldn]
                  (assoc node :children chldn))
                nil)]
    (is (= '{:type      "clone",
             :pid       100,
             :child-pid 101}
          (z/root (fold-event state {:type "clone" :pid 100 :child-pid 101}))))

    (is (= '{:type      "clone",
             :pid       100,
             :child-pid 101,
             :children  ({:type      "clone",
                          :pid       101,
                          :child-pid 102})}
          (z/root (-> state
                    (fold-event {:type "clone" :pid 100 :child-pid 101})
                    (fold-event {:type "clone" :pid 101 :child-pid 102})))))

    (is (= '{:type      "clone",
             :pid       100,
             :child-pid 101,
             :children  ({:type "execve", :pid 101})}
          (z/root (-> state
                    (fold-event {:type "clone" :pid 100 :child-pid 101})
                    (fold-event {:type "execve" :pid 101})))))
    (is (= '{:type      "clone",
             :pid       100,
             :child-pid 101
             :children  ({:type "execve",
                          :pid  101}
                         {:type "execve",
                          :pid  101})}
          (z/root (-> state
                    (fold-event {:type "clone" :pid 100 :child-pid 101})
                    (fold-event {:type "execve" :pid 101})
                    (fold-event {:type "execve" :pid 101})))))))

(run-tests)
