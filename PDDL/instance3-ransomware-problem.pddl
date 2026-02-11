(define (problem instance-3-ransomware)
  (:domain cyber-defense-numeric) 
  (:objects
    CoreServer - node
    Workstation1 Workstation2 - node
    ransomware - malware
  )

  (:init
    ;; Network Setup
    (connected CoreServer Workstation1)
    (connected CoreServer Workstation2)

    ;; Ransomware Infections (Encryption + Infection) 
    (infected CoreServer ransomware)
    (data-encrypted CoreServer)
    (infected Workstation1 ransomware) 
    (clean Workstation2)

    ;; Initialize numeric counters
    (= (bandwidth-used) 0)
    (= (downtime-cost) 0)
    (= (max-bandwidth) 50)

    ;; Priorities
    ;; CoreServer is critical -> High isolation cost (100)
    ;; Workstations are lower priority -> Low isolation cost (10)
    (= (priority-weight CoreServer) 100)
    (= (priority-weight Workstation1) 10)
    (= (priority-weight Workstation2) 10)
  )

  (:goal (and
    (clean CoreServer)
    (not (data-encrypted CoreServer))
    (clean Workstation1)
    (not (isolated CoreServer))
  ))

  ;; METRIC: Minimize the downtime cost 
  (:metric minimize (downtime-cost))
)