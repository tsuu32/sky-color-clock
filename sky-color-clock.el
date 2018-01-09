(require 'cl-lib)
(require 'color)

(defvar sky-color-clock-format "%d %H:%M")
(defvar sky-color-clock-enable-moonphase-emoji t)

;; TODO:
;; - weather and temperature
;;   - lower saturation and less contrast for cloudy days ?
;;   - gradiant with temperature (like Solar weather app)
;; - solar.el, lunar.el has more accurate algorithm

;; ---- utilities

(defun sky-color-clock--make-gradient (&rest color-stops)
  "Make a function which takes a number and returns a color
according to COLOR-STOPS, which is a sorted list of the
form ((NUMBER . COLOR) ...)."
  (unless color-stops
    (error "No color-stops are specified."))
  (let* ((first-color (pop color-stops))
         (last-color first-color))
    `(lambda (x)
       (cond ((<= x ,(car first-color)) ,(cdr first-color))
             ,@(mapcar (lambda (next-color)
                         (prog1
                             `((<= x ,(car next-color))
                               (sky-color-clock--blend-colors
                                ,(cdr last-color) ,(cdr next-color)
                                (/ (- x ,(car last-color)) ,(- (car next-color) (car last-color)))))
                           (setq last-color next-color)))
                       color-stops)
             (t ,(cdr last-color))))))

(defun sky-color-clock--blend-colors (basecolor mixcolor &optional fraction)
  "Blend to colors. FRACTION must be between 0.0 and 1.0,
otherwise result may be broken."
  (cl-destructuring-bind (r g b) (color-name-to-rgb basecolor)
    (cl-destructuring-bind (rr gg bb) (color-name-to-rgb mixcolor)
      (let* ((x (or fraction 0.5)) (y (- 1 x)))
        (color-rgb-to-hex (+ (* r y) (* rr x)) (+ (* g y) (* gg x)) (+ (* b y) (* bb x)))))))

;; ---- sky color

(defvar sky-color-clock--gradient nil
  "A function which converts a float time (12:30 as 12.5, for
example), to a color.")

;;;###autoload
(defun sky-color-clock-initialize (latitude)
  "Initialize sky-color-clock with LATITUDE (in degrees)."
  (let* ((day-of-year                   ; day of year (0-origin)
          (1- (time-to-day-in-year (current-time))))
         (sun-declination               ; declination of the sun
          (degrees-to-radians
           (* -23.44 (cos (degrees-to-radians (* (/ 360 365.0) (+ day-of-year 10)))))))
         (sunset-hour-angle             ; the "Sunrise equation"
          (* (acos (- (* (tan (degrees-to-radians latitude)) (tan sun-declination))))))
         (sunset-time-from-noon         ; rad -> hours
          (* 24 (/ (radians-to-degrees sunset-hour-angle) 360)))
         (sunrise (- 12 sunset-time-from-noon))
         (sunset (+ 12 sunset-time-from-noon)))
    (setq sky-color-clock--gradient
          (sky-color-clock--make-gradient
           (cons (- sunrise 2.0) "#111111")
           (cons (- sunrise 1.5) "#4d548a")
           (cons (- sunrise 1.0) "#c486b1")
           (cons (- sunrise 0.5) "#ee88a0")
           (cons sunrise         "#ff7d75")
           (cons (+ sunrise 0.5) "#f4eeef")
           (cons (- sunset  1.5) "#5dc9f1")
           (cons (- sunset  1.0) "#aeefdf")
           (cons (- sunset  0.5) "#f1e17c")
           (cons sunset          "#f86b10")
           (cons (+ sunset  0.5) "#100028")
           (cons (+ sunset  1.0) "#111111")))))

(defun sky-color-clock--pick-bg-color (time)
  "Corner cases are not supported for now: daytime-length must be
larger than 5 hrs, sunrise time must be smaller than sunset
time (unlike sunrise 23:00 sunset 19:00), sun must rise and
set (no black/white nights) in a day."
  (unless sky-color-clock--gradient
    (error "sky-color-clock-initialize is not called."))
  (cl-destructuring-bind (sec min hour . _) (decode-time time)
    (funcall sky-color-clock--gradient (+ (/ (+ (/ sec 60.0) min) 60.0) hour))))

(defun sky-color-clock--pick-fg-color (color)
  (cl-destructuring-bind (h s l) (apply 'color-rgb-to-hsl (color-name-to-rgb color))
    (apply 'color-rgb-to-hex
           (color-hsl-to-rgb h s (+ l (if (> l 0.5) -0.5 0.5))))))

(defun sky-color-clock-preview (year month day)
  (interactive (list (read-number "year: ") (read-number "month: ") (read-number "day: ")))
  (switch-to-buffer (get-buffer-create "*sky-color-clock*"))
  (erase-buffer)
  (dotimes (hour 23)
    (dolist (min '(0 5 10 15 20 25 30 35 40 45 50 55))
      (insert (sky-color-clock (encode-time 0 min hour day month year)) "\n"))))

;; ---- emoji moonphase

(defconst sky-color-clock--newmoon 6.8576
  "A new moon (1970/01/08 05:35) in days since the epoch.")

(defconst sky-color-clock--moonphase-cycle 29.5306
  "Eclipse (synodic month) cycle in days.")

(defun sky-color--emoji-moonphase (time)
  (let* ((time-in-days (/ (float-time time) 60 60 24))
         (phase (mod (- time-in-days sky-color-clock--newmoon) sky-color-clock--moonphase-cycle)))
    (cond ((<= phase  1.84) "🌑")
          ((<= phase  5.53) "🌒")
          ((<= phase  9.22) "🌓")
          ((<= phase 12.91) "🌔")
          ((<= phase 16.61) "🌕")
          ((<= phase 20.30) "🌖")
          ((<= phase 23.99) "🌗")
          ((<= phase 27.68) "🌘")
          (t                "🌑"))))

;; ---- the clock

(defun sky-color-clock (&optional time)
  "Generate a fontified time string according to
`sky-color-clock-format' and
`sky-color-clock-enable-moonphase-emoji'."
  (let* ((time (or time (current-time)))
         (bg (sky-color-clock--pick-bg-color time))
         (fg (sky-color-clock--pick-fg-color bg))
         (str (concat " " (format-time-string sky-color-clock-format time) " ")))
    (when sky-color-clock-enable-moonphase-emoji
      (setq str (concat " " (sky-color--emoji-moonphase time) str)))
    (propertize str 'face `(:background ,bg :foreground ,fg))))

(provide 'sky-color-clock)
