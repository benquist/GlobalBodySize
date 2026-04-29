# BIEN Data Loader Upload Disconnect Review (2026-04-27)

## Upload Source Clarification
In Shiny, `fileInput()` allows a user to select a file from their own local device (computer/hard drive). The browser then uploads that file to the Shiny server for processing. The app cannot directly browse arbitrary files on the user's disk.

## Symptom Reviewed
Remote user reports:
- File picker selection succeeds
- Progress bar reaches upload complete
- Session then disconnects and reload resets state

## Review Summary
The implemented robustness fix improved parse error handling, but does not fully remove likely disconnect causes on hosted infrastructure.

### Critical Remaining Risk
1. Post-upload memory spike from blank-row filtering
- Current logic materializes full-frame character matrices for trimming/empty-row checks.
- On larger/wider files this can trigger process termination after upload completes.

2. No aggregate cap for multi-file uploads
- Per-file size checks exist, but combined files can still exceed app memory.

### Additional Warnings
1. CSV fallback parsing can read large files multiple times.
2. Upload-back handlers can still ingest large files without strict aggregate guarding.

## Recommended Minimal Next Patch
1. Replace matrix-wide blank-row filtering with a low-copy row-keep strategy.
2. Add total upload-size cap and file-count cap for multi-file uploads.
3. Apply similar guardrails to upload-back handlers.
4. Keep existing user workflow and UI behavior unchanged.

## Review Verdict
Current fix: Partial
Sign-off: FAIL until memory-hardening patch is applied.
