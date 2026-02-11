(define (domain cyber-defense-strips)
  (:requirements :strips :typing :adl :negative-preconditions)

  ;; TYPES: The objects in our world
  (:types
    node - object      ; Computers, Servers, etc.
    malware - object   ; Viruses, Worms, Ransomware
  )

  ;; PREDICATES: True/False statements about the state of the world
  (:predicates
    (connected ?n1 ?n2 - node)       ; Network connection exists
    (infected ?n - node ?m - malware); Node is infected by malware
    (clean ?n - node)                ; Node is virus-free
    (isolated ?n - node)             ; Node is cut off from the network
    (scanned ?n - node)              ; Node has been analyzed
    (data-encrypted ?n - node)       ; Data is locked (Ransomware specific)
    (service-degraded ?n - node)     ; Service is down due to dependency failure
    (is-db ?n - node)                ; Helper predicate to identify Databases
    (depends-on ?n1 ?n2 - node)      ; ADL Dependency: n1 relies on n2
  )

  ;; ACTION: SCAN
  ;; Identifies the status of a node.
  (:action scan
    :parameters (?n - node)
    :precondition (not (isolated ?n))
    :effect (scanned ?n)
  )

  ;; ACTION: ISOLATE
  ;; Cuts network connections to prevent spread.
  ;; ADL FEATURE: Automatically degrades services of dependent nodes.
  (:action isolate
    :parameters (?n - node)
    :precondition (not (isolated ?n))
    :effect (and
      (isolated ?n)
      (not (connected ?n ?n)) ; Logic to represent disconnection
      ;; Conditional Effect: If any node depends on ?n, it becomes degraded.
      (forall (?dep - node)
        (when (depends-on ?dep ?n)
              (service-degraded ?dep)))
    )
  )

  ;; ACTION: PATCH
  ;; Removes malware. Requires the node to be isolated first for safety.
  (:action patch
    :parameters (?n - node ?m - malware)
    :precondition (and (scanned ?n) (isolated ?n) (infected ?n ?m))
    :effect (and
      (clean ?n)
      (not (infected ?n ?m))
    )
  )

  ;; ACTION: RESTORE
  ;; Recovers encrypted data (e.g., from Ransomware).
  (:action restore
    :parameters (?n - node)
    :precondition (and (clean ?n) (data-encrypted ?n))
    :effect (and
      (not (data-encrypted ?n))
    )
  )

  ;; ACTION: RECONNECT
  ;; Brings a node back online.
  ;; ADL FEATURE: Automatically restores services for dependent nodes.
  (:action reconnect
    :parameters (?n - node)
    :precondition (and (clean ?n) (isolated ?n))
    :effect (and
      (not (isolated ?n))
      ;; Conditional Effect: Fixes service degradation for dependent nodes.
      (forall (?dep - node)
        (when (depends-on ?dep ?n)
              (not (service-degraded ?dep))))
    )
  )
)