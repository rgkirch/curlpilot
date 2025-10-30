#!/usr/bin/env bb

(ns user)

(require '[clojure.zip :as z])
(require '[clojure.test :refer [run-tests deftest is]])

(defn fold-event [state event]
  (cond
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
      z/up
      (z/insert-child event)
      z/down)))

(deftest fold-event-test
  (let [state (z/zipper
                (constantly true)
                :children
                (fn [node chldn]
                  (assoc node :children chldn))
                {})]
    (is (= '{:children ({:type "clone",
                         :pid 100,
                         :child-pid 101})}
          (z/root (fold-event state {:type "clone" :pid 100 :child-pid 101}))))

    (is (= '{:children ({:type "clone",
                         :pid 100,
                         :child-pid 101,
                         :children ({:type "clone",
                                     :pid 101,
                                     :child-pid 102})})}
          (z/root (-> state
                    (fold-event {:type "clone" :pid 100 :child-pid 101})
                    (fold-event {:type "clone" :pid 101 :child-pid 102})))))

    (is (= '{:children ({:type "clone",
                         :pid 100,
                         :child-pid 101,
                         :children ({:type "execve", :pid 101})})}
          (z/root (-> state
                    (fold-event {:type "clone" :pid 100 :child-pid 101})
                    (fold-event {:type "execve" :pid 101})))))
    (is (= '{:children ({:type "clone",
                         :pid 100,
                         :child-pid 101
                         :children ({:type "execve",
                                     :pid 101}
                                    {:type "execve",
                                     :pid 101})})}
          (z/root (-> state
                    (fold-event {:type "clone" :pid 100 :child-pid 101})
                    (fold-event {:type "execve" :pid 101})
                    (fold-event {:type "execve" :pid 101})))))))

(run-tests)
