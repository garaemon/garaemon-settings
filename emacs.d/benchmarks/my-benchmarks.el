;;; my-benchmarks.el --- Every benchmark scenario -*- lexical-binding: t; -*-

;;; Commentary:
;; The single module the CI workflow loads.  Requiring a scenario file here
;; registers its scenarios, so adding one takes an edit to this file rather
;; than to the workflow.

;;; Code:

(require 'my-consult-benchmark)
(require 'my-treesit-auto-benchmark)

(provide 'my-benchmarks)
;;; my-benchmarks.el ends here
