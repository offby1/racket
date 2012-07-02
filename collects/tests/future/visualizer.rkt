#lang racket/base 
(require rackunit 
         racket/vector
         racket/future/private/visualizer-drawing
         racket/future/private/visualizer-data 
         racket/future/private/display
         "bad-trace1.rkt")  

(define (compile-trace-data logs) 
  (define tr (build-trace logs)) 
  (define-values (finfo segs) (calc-segments tr)) 
  (values tr 
          finfo 
          segs 
          (frame-info-timeline-ticks finfo)))

;Display tests 
(let ([vr (viewable-region 3 3 500 500)]) 
  (for ([i (in-range 4 503)]) 
    (check-true (in-viewable-region-horiz vr i) 
                (format "~a should be in ~a" 
                        i 
                        vr)))
  (for ([i (in-range 0 2)]) 
    (check-false (in-viewable-region-horiz vr i) 
                 (format "~a should not be in ~a" 
                         i 
                         vr))
  (for ([i (in-range 504 1000)]) 
    (check-false (in-viewable-region-horiz vr i) 
                 (format "~a should not be in ~a" 
                         i 
                         vr)))))

(let ([vr (viewable-region 0 0 732 685)]) 
  (check-true (in-viewable-region-horiz vr 10)) 
  (check-true (in-viewable-region-horiz vr 63.0)) 
  (check-true (in-viewable-region-horiz vr 116.0)) 
  (check-true (in-viewable-region-horiz vr 169.0)) 
  (check-true (in-viewable-region-horiz vr 222)))

(let ([vr (viewable-region 0 0 732 685)] 
      [ticks (list (timeline-tick 222.0 #f 0.4999999999999982) 
                   (timeline-tick 169.0 #f 0.3999999999999986) 
                   (timeline-tick 116.0 #f 0.29999999999999893) 
                   (timeline-tick 63.0 #f 0.1999999999999993) 
                   (timeline-tick 10 #f 0.09999999999999964))]) 
  (define in-vr (filter (λ (t) 
                          (in-viewable-region-horiz vr (timeline-tick-x t))) 
                        ticks)) 
  (check-equal? (length in-vr) 5))

;Trace compilation tests
(let* ([future-log (list (indexed-fevent 0 (future-event 0 0 'create 0 #f 0)) 
                         (indexed-fevent 1 (future-event 0 1 'start-work 1 #f #f)) 
                         (indexed-fevent 2 (future-event 0 1 'end-work 2 #f #f)) 
                         (indexed-fevent 3 (future-event 0 0 'complete 3 #f #f)))] 
       [organized (organize-output future-log)]) 
  (check-equal? (vector-length organized) 2) 
  (let ([proc0log (vector-ref organized 0)] 
        [proc1log (vector-ref organized 1)]) 
    (check-equal? (vector-length proc0log) 2) 
    (check-equal? (vector-length proc1log) 2)))

(let* ([future-log (list (indexed-fevent 0 (future-event #f 0 'create 0 #f 0)) 
                         (indexed-fevent 1 (future-event 0 1 'start-work 1 #f #f)) 
                         (indexed-fevent 2 (future-event 0 1 'end-work 2 #f #f)) 
                         (indexed-fevent 3 (future-event 0 0 'complete 3 #f #f)))] 
       [trace (build-trace future-log)] 
       [evts (trace-all-events trace)])
  (check-equal? (length evts) 4) 
  (check-equal? (length (filter (λ (e) (event-next-future-event e)) evts)) 2) 
  (check-equal? (length (filter (λ (e) (event-next-targ-future-event e)) evts)) 1) 
  (check-equal? (length (filter (λ (e) (event-prev-targ-future-event e)) evts)) 1))

(let* ([future-log (list (indexed-fevent 0 (future-event 0 0 'create 0 #f 0)) 
                         (indexed-fevent 1 (future-event 1 0 'create 1 #f 1)) 
                         (indexed-fevent 2 (future-event 0 1 'start-work 2 #f #f)) 
                         (indexed-fevent 3 (future-event 1 2 'start-work 2 #f #f))
                         (indexed-fevent 4 (future-event 0 1 'end-work 4 #f #f)) 
                         (indexed-fevent 5 (future-event 0 0 'complete 5 #f #f)) 
                         (indexed-fevent 6 (future-event 1 2 'end-work 5 #f #f)) 
                         (indexed-fevent 7 (future-event 1 0 'complete 7 #f #f)))] 
       [organized (organize-output future-log)]) 
  (check-equal? (vector-length organized) 3) 
  (let ([proc0log (vector-ref organized 0)] 
        [proc1log (vector-ref organized 1)] 
        [proc2log (vector-ref organized 2)]) 
    (check-equal? (vector-length proc0log) 4) 
    (check-equal? (vector-length proc1log) 2)
    (check-equal? (vector-length proc2log) 2) 
    (for ([msg (in-vector (vector-map indexed-fevent-fevent proc0log))])  
      (check-equal? (future-event-process-id msg) 0)) 
    (for ([msg (in-vector (vector-map indexed-fevent-fevent proc1log))]) 
      (check-equal? (future-event-process-id msg) 1)) 
    (for ([msg (in-vector (vector-map indexed-fevent-fevent proc2log))]) 
      (check-equal? (future-event-process-id msg) 2))))

;Drawing calculation tests
(let* ([future-log (list (indexed-fevent 0 (future-event #f 0 'create 0 #f 0)) 
                         (indexed-fevent 1 (future-event 0 1 'start-work 1 #f #f)) 
                         (indexed-fevent 2 (future-event 0 1 'end-work 2 #f #f)) 
                         (indexed-fevent 3 (future-event 0 0 'complete 3 #f #f)))] 
       [trace (build-trace future-log)]) 
  (let-values ([(finfo segments) (calc-segments trace)]) 
    (check-equal? (length segments) 4) 
    (check-equal? (length (filter (λ (s) (segment-next-future-seg s)) segments)) 2) 
    (check-equal? (length (filter (λ (s) (segment-next-targ-future-seg s)) segments)) 1) 
    (check-equal? (length (filter (λ (s) (segment-prev-targ-future-seg s)) segments)) 1)))

;Future=42
(let* ([future-log (list (indexed-fevent 0 (future-event #f 0 'create 0.05 #f 42)) 
                         (indexed-fevent 1 (future-event 42 1 'start-work 0.07 #f #f)) 
                         (indexed-fevent 2 (future-event 42 1 'end-work 0.3 #f #f)) 
                         (indexed-fevent 3 (future-event 42 0 'complete 1.2 #f #f)))] 
       [tr (build-trace future-log)])
  (define-values (finfo segs) (calc-segments tr))
  (define ticks (frame-info-timeline-ticks finfo))
  (check-equal? (length ticks) 11))

(define (sanity-check-ticks ticks)
  (define ticks-in-ascending-time-order (reverse ticks))
  (let loop ([cur (car ticks-in-ascending-time-order)] 
             [rest (cdr ticks-in-ascending-time-order)]) 
    (unless (null? rest) 
      (define next (car rest))
      (check-true (>= (timeline-tick-x next) (timeline-tick-x cur)) 
                  (format "Tick at time ~a [x:~a] had x-coord less than previous tick: ~a [x:~a]" 
                          (exact->inexact (timeline-tick-rel-time next)) 
                          (timeline-tick-x next) 
                          (exact->inexact (timeline-tick-rel-time cur)) 
                          (timeline-tick-x cur)))
      (loop next 
            (cdr rest)))))

;;do-seg-check : trace segment timeline-tick (a a -> bool) string -> void
(define (do-seg-check tr seg tick op adjective) 
  (define evt (segment-event seg))
  (check-true (op (segment-x seg) (timeline-tick-x tick)) 
              (format "Event at time ~a [x:~a] (~a) should be ~a tick at time ~a [x:~a]"
                      (relative-time tr (event-start-time evt))
                      (segment-x seg)
                      (event-type evt)
                      adjective
                      (exact->inexact (timeline-tick-rel-time tick)) 
                      (timeline-tick-x tick))))

;;check-seg-layout : trace (listof segment) (listof timeline-tick) -> void
(define (check-seg-layout tr segs ticks) 
  (for ([seg (in-list segs)])
    (define evt-rel-time (relative-time tr (event-start-time (segment-event seg))))
      (for ([tick (in-list ticks)]) 
        (define ttime (timeline-tick-rel-time tick))
          (cond 
            [(< evt-rel-time ttime) 
             (do-seg-check tr seg tick <= "before")] 
            [(= evt-rel-time ttime) 
             (do-seg-check tr seg tick = "equal to")]
            [(> evt-rel-time ttime) 
             (do-seg-check tr seg tick >= "after")]))))

;Test layout for 'bad' mandelbrot trace 
(let-values ([(tr finfo segs ticks) (compile-trace-data BAD-TRACE-1)]) 
  (sanity-check-ticks ticks)
  (check-seg-layout tr segs ticks))
             
(let* ([future-log (list (indexed-fevent 0 (future-event #f 0 'create 0.05 #f 42)) 
                         (indexed-fevent 1 (future-event 42 1 'start-work 0.09 #f #f)) 
                         (indexed-fevent 2 (future-event 42 1 'suspend 1.1 #f #f)) 
                         (indexed-fevent 3 (future-event 42 1 'resume 1.101 #f #f)) 
                         (indexed-fevent 4 (future-event 42 1 'suspend 1.102 #f #f)) 
                         (indexed-fevent 5 (future-event 42 1 'resume 1.103 #f #f)) 
                         (indexed-fevent 6 (future-event 42 1 'start-work 1.104 #f #f)) 
                         (indexed-fevent 7 (future-event 42 1 'complete 1.41 #f #f)) 
                         (indexed-fevent 8 (future-event 42 1 'end-work 1.42 #f #f)) 
                         (indexed-fevent 9 (future-event 42 0 'result 1.43 #f #f)))] 
       [tr (build-trace future-log)]) 
  (define-values (finfo segs) (calc-segments tr)) 
  (define ticks (frame-info-timeline-ticks finfo))
  (check-seg-layout tr segs ticks))

(let* ([future-log (list (indexed-fevent 0 (future-event #f 0 'create 0 #f 0)) 
                         (indexed-fevent 1 (future-event 0 1 'start-work 1 #f #f)) 
                         (indexed-fevent 2 (future-event 0 1 'end-work 2 #f #f)) 
                         (indexed-fevent 3 (future-event 0 0 'complete 3 #f #f)))] 
       [trace (build-trace future-log)]) 
  (check-equal? (trace-start-time trace) 0) 
  (check-equal? (trace-end-time trace) 3) 
  (check-equal? (length (trace-proc-timelines trace)) 2) 
  (check-equal? (trace-real-time trace) 3) 
  (check-equal? (trace-num-futures trace) 1) 
  (check-equal? (trace-num-blocks trace) 0) 
  (check-equal? (trace-num-syncs trace) 0) 
  (let ([proc0tl (list-ref (trace-proc-timelines trace) 0)] 
        [proc1tl (list-ref (trace-proc-timelines trace) 1)]) 
    (check-equal? (process-timeline-start-time proc0tl) 0) 
    (check-equal? (process-timeline-end-time proc0tl) 3) 
    (check-equal? (process-timeline-start-time proc1tl) 1) 
    (check-equal? (process-timeline-end-time proc1tl) 2) 
    (let ([proc0segs (process-timeline-events proc0tl)] 
          [proc1segs (process-timeline-events proc1tl)]) 
      (check-equal? (length proc0segs) 2) 
      (check-equal? (length proc1segs) 2)
      (check-equal? (event-timeline-position (list-ref proc0segs 0)) 'start) 
      (check-equal? (event-timeline-position (list-ref proc0segs 1)) 'end)))) 

;Viewable region tests 
(define (make-seg-at x y w h) 
  (segment #f x y w h #f #f #f #f #f #f #f #f))

;;make-segs-with-times : (listof (or float (float . float))) -> (listof segment)
(define (make-segs-with-times . times) 
  (for/list ([t (in-list times)] [i (in-naturals)]) 
    (if (pair? t) 
        (make-seg-with-time i (car t) #:end-time (cdr t)) 
        (make-seg-with-time i t))))

;;make-seg-with-time : fixnum float [float] -> segment
(define (make-seg-with-time index real-start-time #:end-time [real-end-time real-start-time]) 
  (segment (event index
                  real-start-time 
                  real-end-time 
                  0 0 0 0 0 0 0 0 0 0 0 0 0 #f) 
           0 0 0 0 #f #f #f #f #f #f #f #f))
                   

(let ([vregion (viewable-region 20 30 100 100)] 
      [seg1 (make-seg-at 0 5 10 10)] 
      [seg2 (make-seg-at 20 30 5 5)] 
      [seg3 (make-seg-at 150 35 5 5)]) 
  (check-false ((seg-in-vregion vregion) seg1)) 
  (check-true ((seg-in-vregion vregion) seg2)) 
  (check-false ((seg-in-vregion vregion) seg3)))

;segs-equal-or-later 
(let ([segs (make-segs-with-times 0.1 
                                  0.3 
                                  1.2 
                                  (cons 1.4 1.9) 
                                  2.4 
                                  2.8 
                                  3.1)]) 
  (check-equal? (length (segs-equal-or-later 0.1 segs)) 7) 
  (check-equal? (length (segs-equal-or-later 0.3 segs)) 6) 
  (check-equal? (length (segs-equal-or-later 1.2 segs)) 5) 
  (check-equal? (length (segs-equal-or-later 1.4 segs)) 4) 
  (check-equal? (length (segs-equal-or-later 2.4 segs)) 3) 
  (check-equal? (length (segs-equal-or-later 2.8 segs)) 2) 
  (check-equal? (length (segs-equal-or-later 3.1 segs)) 1) 
  (check-equal? (length (segs-equal-or-later 4.0 segs)) 0))

;Tick drawing  
(let ([l (list (indexed-fevent 0 (future-event #f 0 'create 10.0 #f 0))
               (indexed-fevent 1 (future-event 0 0 'start-work 11.0 #f #f)) 
               (indexed-fevent 2 (future-event 0 0 'end-work 20.0 #f #f)))])
  (define-values (tr finfo segs ticks) (compile-trace-data l)) 
  ;Check that number of ticks stays constant whatever the time->pixel modifier 
  (check-equal? (length ticks) 100)
  (check-equal? (length (calc-ticks segs 700 tr)) 100)
  (for ([i (in-range 0.1 20)]) 
    (check-equal? (length (calc-ticks segs i tr)) 
                  100 
                  (format "Wrong number of ticks for time->pix mod ~a\n" i)))
  (check-seg-layout tr segs ticks))

(let ([l (list (indexed-fevent 0 '#s(future-event #f 0 create 1334778395768.733 #f 3))
               (indexed-fevent 1 '#s(future-event 3 2 start-work 1334778395768.771 #f #f))
               (indexed-fevent 2 '#s(future-event 3 2 complete 1334778395864.648 #f #f))
               (indexed-fevent 3 '#s(future-event 3 2 end-work 1334778395864.652 #f #f)))]) 
  (define-values (tr finfo segs ticks) (compile-trace-data l))
  (define last-evt (indexed-fevent-fevent (list-ref l 3))) 
  (define first-evt (indexed-fevent-fevent (list-ref l 0))) 
  (define total-time (- (future-event-time last-evt) (future-event-time first-evt))) 
  (check-equal? (length ticks) (inexact->exact (floor (* 10 total-time)))))

(define mand-first 
  (list (indexed-fevent 0 '#s(future-event #f 0 create 1334779294212.415 #f 1))
        (indexed-fevent 1 '#s(future-event 1 1 start-work 1334779294212.495 #f #f))
        (indexed-fevent 2 '#s(future-event 1 1 sync 1334779294212.501 #f #f))
        (indexed-fevent 3 (future-event 1 0 'sync 1334779294221.128 'allocate_memory #f))
        (indexed-fevent 4 '#s(future-event 1 0 result 1334779294221.138 #f #f))
        (indexed-fevent 5 '#s(future-event 1 1 result 1334779294221.15 #f #f)))) 
(let-values ([(tr finfo segs ticks) (compile-trace-data mand-first)]) 
  (check-seg-layout tr segs ticks))

(define single-block-log 
  (list
   (indexed-fevent 0 '#s(future-event #f 0 create 1339469018856.55 #f 1))
   (indexed-fevent 1 '#s(future-event 1 1 start-work 1339469018856.617 #f 0))
   (indexed-fevent 2 '#s(future-event 1 1 block 1339469018856.621 #f 0))
   (indexed-fevent 3 '#s(future-event 1 1 suspend 1339469018856.891 #f 0))
   (indexed-fevent 4 '#s(future-event 1 1 end-work 1339469018856.891 #f 0))
   (indexed-fevent 5 '#s(future-event 1 0 block 1339469019057.609 printf 0))
   (indexed-fevent 6 '#s(future-event 1 0 result 1339469019057.783 #f 0))
   (indexed-fevent 7 '#s(future-event 1 2 start-work 1339469019057.796 #f 0))
   (indexed-fevent 8 '#s(future-event 1 2 complete 1339469019057.799 #f 0))
   (indexed-fevent 9 '#s(future-event 1 2 end-work 1339469019057.801 #f 0)))) 
(let ([tr (build-trace single-block-log)]) 
  (check-equal? (length (hash-keys (trace-block-counts tr))) 1) 
  (check-equal? (length (hash-keys (trace-sync-counts tr))) 0) 
  (check-equal? (length (hash-keys (trace-future-rtcalls tr))) 1))



  
