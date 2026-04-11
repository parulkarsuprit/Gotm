# Known Issues

## First-Launch Transcription Delay
**Status:** Documented, to be fixed in Performance phase  
**Impact:** ~3-5 second delay on first recording after app launch  
**Cause:** SFSpeechRecognizer loads on-device speech model on first use  
**Workaround:** None currently. Model stays warm after first use.  
**Future Fix:** Pre-warm speech recognizer at app launch (requires startup optimization work)
