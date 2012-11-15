#lang racket/base

(require racket/list
         racket/class
         racket/match
         racket/pretty
         racket/gui/base
#;         framework/private/logging-timer)

#|

This file sets up a log receiver and then
starts up DrRacket. It catches log messages and 
organizes them on event boundaries, printing
out the ones that take the longest
(possibly dropping those where a gc occurs)

The result shows, for each gui event, the
log messages that occured during its dynamic
extent as well as the number of milliseconds
from the start of the gui event before the
log message was reported.

|#


(define lr (make-log-receiver (current-logger)
                              'debug 'racket/engine
                              'debug 'GC
                              'debug 'gui-event
                              'debug 'framework/colorer
                              'debug 'timeline))

(define top-n-events 50)
(define drop-gc? #f)
(define start-right-away? #t) ;; only applies if the 'main' module is loaded
(define show-hist? #f)
(define script-drr? #t)

(define log-done-chan (make-channel))
(define bt-done-chan (make-channel))

(define start-log-chan (make-channel))
(void 
 (thread
  (λ ()
    (let loop () 
      (sync start-log-chan)
      (let loop ([events '()])
        (sync
         (handle-evt
          lr
          (λ (info)
            (loop (cons info events))))
         (handle-evt
          log-done-chan
          (λ (resp-chan)
            (channel-put resp-chan events)))))
      (loop)))))

(define thread-to-watch (current-thread))
(let ([win (get-top-level-windows)])
  (unless (null? win)
    (define fr-thd (eventspace-handler-thread (send (car win) get-eventspace)))
    (unless (eq? thread-to-watch fr-thd)
      (eprintf "WARNING: current-thread and eventspace thread aren't the same thread\n"))))
(define start-bt-chan (make-channel))
(void 
 (thread
  (λ ()
    (let loop () 
      (sync start-bt-chan)
      (let loop ([marks '()])
        (sync
         (handle-evt
          (alarm-evt (+ (current-inexact-milliseconds) 10))
          (λ (_)
            (loop (cons (continuation-marks thread-to-watch)
                        marks))))
         (handle-evt
          bt-done-chan
          (λ (resp-chan)
            (define stacks (map continuation-mark-set->context marks))
            (channel-put resp-chan stacks)))))
      (loop)))))

(define controller-frame-eventspace (make-eventspace))
(define f (parameterize ([current-eventspace controller-frame-eventspace])
            (new frame% [label "Log Follower"])))
(define sb (new button% [label "Start Following Log"] [parent f]
               [callback
                (λ (_1 _2)
                  (sb-callback))]))
(define sb2 (new button% [label "Start Collecting Backtraces"] [parent f]
                 [callback
                  (λ (_1 _2)
                    (start-bt-callback))]))
(define db (new button% [label "Stop && Dump"] [parent f] [enabled #f]
                [callback
                 (λ (_1 _2)
                   (stop-and-dump))]))
(define (stop-and-dump)
  (cond
    [following-log?
     (define resp (make-channel))
     (channel-put log-done-chan resp)
     (show-results (channel-get resp))
     (send db enable #f)
     (send sb enable #t)
     (send sb2 enable #t)
     (set! following-log? #f)]
    [following-bt?
     (define resp (make-channel))
     (channel-put bt-done-chan resp)
     (define stacks (channel-get resp))
     (show-bt-results stacks)
     (send db enable #f)
     (send sb enable #t)
     (send sb2 enable #t)
     (set! following-bt? #f)]))

(define following-log? #f)
(define following-bt? #f)

(define (sb-callback)
  (set! following-log? #t)
  (send sb enable #f)
  (send sb2 enable #f)
  (send db enable #t)
  (channel-put start-log-chan #t))

(define (start-bt-callback)
  (set! following-bt? #t)
  (send sb enable #f)
  (send sb2 enable #f)
  (send db enable #t)
  (channel-put start-bt-chan #t))

(send f show #t)

(define (show-bt-results stacks)
  (define top-frame (make-hash))
  (for ([stack (in-list stacks)])
    (unless (null? stack)
      (define k (car stack))
      (hash-set! top-frame k (cons stack (hash-ref top-frame k '())))))
  (define sorted (sort (hash-map top-frame (λ (x y) y)) > #:key length))
  (printf "top 10: ~s\n" (map length (take sorted (min (length sorted) 10))))
  (define most-popular (cadr sorted))
  (for ([x (in-range 10)])
    (printf "---- next stack\n")
    (pretty-print (list-ref most-popular (random (length most-popular))))
    (printf "\n"))
  (void))

(struct gui-event (start end name) #:prefab)

(define (show-results evts)
  (define gui-events (filter (λ (x) 
                               (define i (vector-ref x 2))
                               (and (gui-event? i)
                                    (number? (gui-event-end i))))
                             evts))
  
  (cond
    [show-hist?
     
     (define bucket-size 2) ;; in milliseconds
     (define (δ->bucket δ)
       (* bucket-size
          (inexact->exact (round (* δ (/ 1.0 bucket-size))))))
     
     (define buckets (make-hash))
     (for ([vec (in-list gui-events)])
       (define gui-event (vector-ref vec 2))
       (define bucket (δ->bucket
                       (- (gui-event-end gui-event)
                          (gui-event-start gui-event))))
       (hash-set! buckets bucket (+ (hash-ref buckets bucket 0) 1)))
     (pretty-print
      (sort (hash-map buckets vector)
            <
            #:key (λ (x) (vector-ref x 0))))]
    [else
     
     
     (define interesting-gui-events
       (take (sort gui-events > #:key (λ (x) 
                                        (define i (vector-ref x 2))
                                        (- (gui-event-end i)
                                           (gui-event-start i))))
             top-n-events))
     
     (define with-other-events
       (for/list ([gui-evt (in-list interesting-gui-events)])
         (match (vector-ref gui-evt 2)
           [(gui-event start end name)
            (define in-the-middle
              (append (map (λ (x) (list (list 'δ (- (get-start-time x) start)) x))
                           (sort
                            (filter (λ (x) (and (not (gui-event? (vector-ref x 2)))
                                                (<= start (get-start-time x) end)))
                                    evts)
                            <
                            #:key get-start-time))
                      (list (list (list 'δ (- end start)) 'end-of-gui-event))))
            (list* (- end start)
                   gui-evt
                   in-the-middle)])))
     
     (define (has-a-gc-event? x)
       (define in-the-middle (cddr x))
       (ormap (λ (x) 
                (and (vector? (list-ref x 1))
                     (gc-info? (vector-ref (list-ref x 1) 2))))
              in-the-middle))
     
     (pretty-print
      (if drop-gc?
          (filter (λ (x) (not (has-a-gc-event? x)))
                  with-other-events)
          with-other-events))]))

(struct gc-info (major? pre-amount pre-admin-amount code-amount
                        post-amount post-admin-amount
                        start-process-time end-process-time
                        start-time end-time)
  #:prefab)
(struct engine-info (msec name) #:prefab)

(define (get-start-time x)
  (cond
    [(gc-info? (vector-ref x 2))
     (gc-info-start-time (vector-ref x 2))]
    [(engine-info? (vector-ref x 2))
     (engine-info-msec (vector-ref x 2))]
    [(regexp-match #rx"framework" (vector-ref x 1))
     (vector-ref x 2)]
#;
    [(timeline-info? (vector-ref x 2))
     (timeline-info-milliseconds (vector-ref x 2))]         
    [else
     (unless (regexp-match #rx"^GC: 0:MST @" (vector-ref x 1))
       (eprintf "unk: ~s\n" x))
     0]))

(define drr-eventspace (current-eventspace))
(require (file "/Users/robby/git/plt/collects/tests/drracket/private/drracket-test-util.rkt")
         framework/test)

(test:use-focus-table #t)

;; running on controller-frame-eventspace handler thread
(define (run-drracket-script)
  (test:use-focus-table #t)
  (test:current-get-eventspaces (λ () (list drr-eventspace)))
  (define drr (wait-for-drracket-frame))
  
  (define (wait-until something)
    (define chan (make-channel))
    (let loop ()
      (sleep 1)
      (parameterize ([current-eventspace drr-eventspace])
        (queue-callback
         (λ () 
           (channel-put chan (something)))))
      (unless (channel-get chan)
        (loop))))
  
  (define (online-syncheck-done)
    (define-values (colors labels) (send (send drr get-current-tab) get-bkg-running))
    (equal? colors '("forestgreen")))
  
  (define (syntax-coloring-done)
    (send (send drr get-definitions-text) is-lexer-valid?))
  
  (sync
   (thread
    (λ ()
      (current-eventspace drr-eventspace)
      (test:current-get-eventspaces (λ () (list drr-eventspace)))
      (test:use-focus-table #t)
      (test:menu-select "View" "Hide Interactions")
      
      
      (define s (make-semaphore))
      (parameterize ([current-eventspace drr-eventspace])
        (queue-callback
         (λ () 
           (define defs (send drr get-definitions-text))
           (send defs load-file (collection-file-path "class-internal.rkt" "racket" "private"))
           (send defs set-position 395)
           (send (send defs get-canvas) focus)
           (semaphore-post s)))
        #f)
      (semaphore-wait s)

      ;(wait-until online-syncheck-done)
      
      (for ([x (in-range 10)])
        
        (let ([s "fdjafjdklafjkdalsfjdaklfjdkaslfdjafjdklafjkdalsfjdaklfjdkasl"])
          (for ([c (in-string s)])
            (test:keystroke c))
          (for ([c (in-string s)])
            (test:keystroke #\backspace)))
        
        (test:keystroke #\")
        (test:keystroke #\a)
        (wait-until syntax-coloring-done)
        (test:keystroke #\backspace)
        (test:keystroke #\backspace)
        (wait-until online-syncheck-done)) 
      (sleep 10)))) ;; let everything finish
  
  (stop-and-dump)
  (exit))
    
(module+ main
  (when start-right-away?
    (parameterize ([current-eventspace controller-frame-eventspace])
      (queue-callback sb-callback)))
  (dynamic-require 'drracket #f)
  (when script-drr?
    (parameterize ([current-eventspace controller-frame-eventspace])
      (queue-callback
       (λ () 
         (run-drracket-script))))))