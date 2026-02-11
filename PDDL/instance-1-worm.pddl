(define (problem instance-1-worm)
  (:domain cyber-defense-strips)
  (:objects
    nodeA nodeB nodeC - node
    worm - malware
  )

  (:init
    ;; Network Topology (Linear): A -> B -> C 
    (connected nodeA nodeB)
    (connected nodeB nodeC)

    ;; Initial Infection Status: Node A is infected 
    (infected nodeA worm)

    ;; No numeric values here. Only logical predicates.
    ;; Explicitly defining clean nodes.
    (clean nodeB)
    (clean nodeC)
  )

  (:goal (and
    (clean nodeA)           ; Node A must be cured
    (clean nodeC)           ; Node C must remain clean
    (not (isolated nodeA))  ; Node A must be back online
  ))
)