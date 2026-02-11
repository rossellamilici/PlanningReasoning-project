(define (domain cyber-defense-numeric)
  (:requirements :strips :typing :adl :negative-preconditions :numeric-fluents)

  (:types
    node - object
    malware - object
  )

  (:predicates
    (connected ?n1 ?n2 - node)
    (infected ?n - node ?m - malware)
    (clean ?n - node)
    (isolated ?n - node)
    (scanned ?n - node)
    (data-encrypted ?n - node)
    (service-degraded ?n - node)
    (depends-on ?n1 ?n2 - node)
  )

  ;; FUNCTIONS (Numeric Fluents)
  ;; Used to track resources and optimization metrics
  (:functions
    (bandwidth-used)            ;; Total bandwidth consumed by actions 
    (max-bandwidth)
    (downtime-cost)             ;; Accumulated cost of service interruption
    (priority-weight ?n - node) ;; Static value of a node (Cost per isolation) 
  )

  (:action scan
    :parameters (?n - node)
    :precondition (not (isolated ?n))
    :effect (scanned ?n)
  )

  (:action isolate
    :parameters (?n - node)
    :precondition (not (isolated ?n))
    :effect (and
      (isolated ?n)
      ;; COST LOGIC: Isolating a node increases downtime cost based on its priority.
      ;; High-value nodes (like CoreServer) are more expensive to isolate.
      (increase (downtime-cost) (priority-weight ?n))
      ;; ADL FEATURE: Degrade dependent services
      (forall (?dep - node)
        (when (depends-on ?dep ?n)
              (service-degraded ?dep)))
    )
  )


  ;; Patching is lightweight: Consumes 5 bandwidth units 
  (:action patch
    :parameters (?n - node ?m - malware)
    :precondition (and (scanned ?n) (isolated ?n) (infected ?n ?m) (<= (+ (bandwidth-used) 5)     (max-bandwidth)))
    :effect (and
      (clean ?n)
      (not (infected ?n ?m))
      (increase (bandwidth-used) 5)
    )
  )

  ;; Restore is heavy: Consumes 20 bandwidth units 
  (:action restore
    :parameters (?n - node)
    :precondition (and (clean ?n) (data-encrypted ?n) (<= (+ (bandwidth-used) 20) (max-bandwidth)))
    :effect (and
      (not (data-encrypted ?n))
      (increase (bandwidth-used) 20)
    )
  )

  (:action reconnect
    :parameters (?n - node)
    :precondition (and (clean ?n) (isolated ?n))
    :effect (and
      (not (isolated ?n))
      ;; ADL FEATURE: Restore dependent services
      (forall (?dep - node)
        (when (depends-on ?dep ?n)
              (not (service-degraded ?dep))))
    )
  )
)