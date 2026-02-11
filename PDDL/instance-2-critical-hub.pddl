(define (problem instance-2-critical-hub)
  (:domain cyber-defense-strips)
  (:objects
    DB Web1 Web2 - node
    worm - malware
  )

  (:init
    ;; Star Topology: DB is the center 
    (connected DB Web1)
    (connected DB Web2)
    
    ;; ADL Dependencies: Web Servers rely on the DB 
    ;; If DB is isolated, Web1 and Web2 will become (service-degraded).
    (depends-on Web1 DB)
    (depends-on Web2 DB)

    ;; Infection: The Database is compromised
    (infected DB worm)
    
    ;; Initial clean state for other nodes
    (clean Web1)
    (clean Web2)
  )

  (:goal (and
    (clean DB)                    ;; DB must be cleaned 
    (not (isolated DB))           ;; DB must be reconnected to the network
    (not (service-degraded Web1)) ;; Web1 service must be restored
    (not (service-degraded Web2)) ;; Web2 service must be restored
  ))
)