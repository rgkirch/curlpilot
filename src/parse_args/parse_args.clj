(ns arg-parser
  (:require [clojure.string :as str]
            [cheshire.core :as json]))

(defn key? [s]
  (string/starts-with? "--"))

(defn flag->key [s]
  (-> s
    (string/replace "^--" "")
    (string/replace "-" "_")))

(defn split-key [s]
  (string/split s #"=" 2))

(defn compound? [s]
  (string/includes s "="))

(defn parse-args-helper
  [{:keys [spec args]}]
  (if (empty? args)
    spec
    (let [[k tail] [(first args) (rest args)]
          [k v tail]
          (cond
            (compound? k)
            (concat (split-key k) tail)

            (and (key? (first tail))
              (= (get-in spec [(flag->key k) "type"]) "boolean"))
            [k true tail]

            (key? (first tail))
            (throw (ex-info "missing value" {:key k}))

            :else
            (concat [k (first tail)] (rest tail)))]
      (recur {:spec (assoc-in spec [(flag->key k) "value"] v)
              :args tail}))))

(defn ensure-values
  [spec]
  (reduce-kv (fn [m k v]
               (let [required? (not (contains? v "default"))
                     missing?  (not (contains? v "value"))
                     default   (get v "default")]
                 (cond
                   (and missing? required?) (throw (ex-info "missing required value" {:key k}))
                   missing?                 (assoc m k (assoc v "value" default))
                   :else                    (assoc m k v))))
    {}
    spec))

;; (defn ensure-values
;;   [{:keys [spec] :as m}]
;;   (assoc m
;;     (into {}
;;       (for [[k v] spec
;;             :let  [required? (not (contains? (get spec k) "default"))
;;                   missing? (not (contains? (get spec k) "value"))
;;                   default (get-in spec [k "default"])]]
;;         (cond
;;           (and missing? required?) (throw (ex-info "missing required value" {:key k}))
;;           missing?                 [k (assoc v "value" default)]
;;           :else                    [k v])))))



(defn- parse-token [token]
  (let [stripped          (subs token 2)
        [key-str val-str] (str/split stripped #"=" 2)]
    {:key (-> key-str
            (str/replace "-" "_")
            (keyword))
     :value val-str}))

(defn- coerce-value [value-str type-str]
  (case type-str
    "boolean" (read-string value-str)   ; Parses true or false
    "json"    (if (= value-str "-")
                value-str                           ; Pass "-" through for stdin
                (json/parse-string value-str true)) ; The `true` keywordizes keys
    value-str)) ; Default is string

(defn parse-args
  "Parses a list of command-line arguments against a specification.
  Expects a map with :spec and :args keys."
  [{:keys [spec args]}]
  (loop [current-spec spec
         remaining-args args]
    (if (empty? remaining-args)
      current-spec
      (let [[current-arg & next-args] remaining-args
            {:keys [key value]} (parse-token current-arg)
            spec-entry (get current-spec key)]
        (let [[value-str args-for-next-loop]
              (cond
                value
                [value next-args]

                (and (first next-args) (not (str/starts-with? (first next-args) "--")))
                [(first next-args) (rest next-args)]

                :else
                [(if (= (:type spec-entry) "boolean") "true" (:default spec-entry))
                 next-args])]

          ;; Coerce the value and update the spec for the next iteration.
          (let [coerced (coerce-value value-str (:type spec-entry))
                new-spec (assoc-in current-spec [key :value] coerced)]
            ;; Recurse with the updated spec and the remaining args.
            (recur new-spec args-for-next-loop)))))))
