;;; early-init.el --- Early initialization -*- lexical-binding: t -*-

;;; Commentary:
;; This file is loaded before package initialization and GUI creation.
;; It contains settings that must run before the main init.el.

;;; Code:

;; Disable package.el in favor of manual control
(setq package-enable-at-startup nil)

;; Work around older GCC/libgccjit versions incorrectly inferring the macOS
;; deployment target from the Darwin kernel version. Use the actual macOS
;; version instead, while preserving any explicitly configured target.
(when (and (eq system-type 'darwin)
           (not (getenv "MACOSX_DEPLOYMENT_TARGET")))
  (setenv "MACOSX_DEPLOYMENT_TARGET"
          (car (process-lines "/usr/bin/sw_vers" "-productVersion"))))

;; Prefer the newer of .el / .elc when loading, so a forgotten stale .elc
;; never overrides edits to the source. The default `nil' silently uses the
;; older byte-compiled file (only warning), which has bitten us before.
(setq load-prefer-newer t)

;; GC optimization for startup
(setq gc-cons-threshold most-positive-fixnum
      gc-cons-percentage 0.6)

;; Disable GUI elements early to prevent flashing
(push '(menu-bar-lines . 0) default-frame-alist)
(push '(tool-bar-lines . 0) default-frame-alist)
(push '(vertical-scroll-bars) default-frame-alist)

;; Native compilation settings
(when (fboundp 'native-comp-available-p)
  (setq native-comp-deferred-compilation nil
        native-comp-async-report-warnings-errors nil))

;; Disable startup screen
(setq inhibit-startup-screen t
      inhibit-startup-message t)

;; Disable GUI elements
(when (fboundp 'tool-bar-mode) (tool-bar-mode -1))
(when (fboundp 'scroll-bar-mode) (scroll-bar-mode -1))
(when (fboundp 'menu-bar-mode) (menu-bar-mode -1))

;;; early-init.el ends here
