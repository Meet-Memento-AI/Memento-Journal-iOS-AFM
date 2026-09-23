# App Store Connect Rejection Fix Guide

**Submission ID**: c96f3d15-5c5c-4acc-9182-b2faf3aacff4
**Review Date**: November 11, 2025
**Version**: 1.0

## Issue 1: Privacy - App Tracking Transparency (Guideline 5.1.2)

### Problem
App Store Connect privacy labels indicate tracking (Performance Data, Email Address, Name), but the app doesn't implement App Tracking Transparency (ATT) framework.

### Root Cause Analysis
**withMemento does NOT track users**. The app:
- ✅ Collects email, name for authentication (Supabase Auth)
- ✅ Stores journal entries in user's private database
- ✅ Does NOT share data with third parties for advertising
- ✅ Does NOT link data with third-party data for tracking
- ✅ Does NOT use analytics services (no Firebase, Mixpanel, Amplitude, etc.)
- ✅ Does NOT have ATT permission string in Info.plist

### Solution: Update Privacy Labels in App Store Connect

The privacy labels were **incorrectly configured**. Here's what to update:

#### Data Collection (What withMemento Actually Collects)

1. **Contact Info**
   - Email Address: ✅ Collected
   - Name: ✅ Collected
   - Purpose: Account Creation, App Functionality
   - Linked to User: YES
   - Used for Tracking: **NO** ❌

2. **User Content**
   - Audio Data: ✅ Collected (voice recordings for journal transcription)
   - Other User Content: ✅ Collected (journal entries, insights)
   - Purpose: App Functionality
   - Linked to User: YES
   - Used for Tracking: **NO** ❌

3. **Identifiers**
   - User ID: ✅ Collected (Supabase user UUID)
   - Purpose: App Functionality
   - Linked to User: YES
   - Used for Tracking: **NO** ❌

4. **Usage Data**
   - Product Interaction: ✅ Collected (entry counts, subscription status)
   - Purpose: App Functionality, Analytics (first-party only)
   - Linked to User: YES
   - Used for Tracking: **NO** ❌

5. **Purchases**
   - Purchase History: ✅ Collected (subscription status)
   - Purpose: App Functionality
   - Linked to User: YES
   - Used for Tracking: **NO** ❌

#### What to REMOVE from Privacy Labels

❌ **Performance Data** - We don't collect crash data or diagnostics
❌ **Any "Used for Tracking" checkboxes** - We don't track users

### Steps to Fix in App Store Connect

1. Log in to [App Store Connect](https://appstoreconnect.apple.com)
2. Go to: **My Apps** → **withMemento** → **App Privacy**
3. Click **Edit** on the privacy section
4. **Remove or uncheck "Used for Tracking"** for ALL data types
5. Ensure only the following are marked as collected:
   - Contact Info (Email, Name) - NOT for tracking
   - User Content (Audio, Journal Entries) - NOT for tracking
   - Identifiers (User ID) - NOT for tracking
   - Usage Data (Product Interaction) - NOT for tracking
   - Purchases (Subscription) - NOT for tracking
6. Save changes

### How to Respond to App Review

**Option 1: Update Privacy Labels** (Recommended)

Reply in App Store Connect:
```
Hello App Review Team,

Thank you for your feedback. We have reviewed our app privacy information and found
it was incorrectly configured.

withMemento does NOT track users. The app:
- Does NOT share user data with third parties for advertising
- Does NOT link data with third-party data for tracking purposes
- Does NOT use any third-party analytics or tracking SDKs

We have updated our App Privacy Information in App Store Connect to accurately
reflect that no data is used for tracking. All data collection (email, name,
journal content) is solely for app functionality and authentication.

Please review the updated privacy labels.

Thank you,
[Your Name]
```

---

## Issue 2: Support URL (Guideline 1.5)

### Problem
Support URL `https://sebmendo1.github.io/withMemento/` is just a landing page without functional support information.

### Solution: Create Dedicated Support Page

I'll create a new support page at: `https://sebmendo1.github.io/withMemento/support.html`

#### Support Page Must Include:
- ✅ Contact email address
- ✅ Support request method (email form or mailto link)
- ✅ FAQ section
- ✅ Common troubleshooting tips
- ✅ Feature documentation
- ✅ Links to Terms & Privacy

### Steps to Fix

1. **Create support.html** (see next file)
2. **Upload to GitHub Pages** (sebmendo1/withMemento repository)
3. **Update App Store Connect**:
   - Go to **App Information** → **Support URL**
   - Change from: `https://sebmendo1.github.io/withMemento/`
   - Change to: `https://sebmendo1.github.io/withMemento/support.html`
4. **Save and resubmit**

---

## Timeline to Fix

- [x] Identify issues (completed)
- [ ] Create support page HTML (5 min)
- [ ] Upload support page to GitHub Pages (2 min)
- [ ] Update App Store Connect privacy labels (10 min)
- [ ] Update App Store Connect support URL (2 min)
- [ ] Reply to App Review with explanation (5 min)
- [ ] Resubmit app for review

**Total Time**: ~30 minutes

---

## Prevention for Future Submissions

### Before Each Submission:
1. ✅ Review App Privacy labels - ensure "Used for Tracking" is NEVER checked unless implementing ATT
2. ✅ Test support URL - ensure it has functional contact information
3. ✅ Review all URLs in App Store Connect (support, marketing, privacy, terms)
4. ✅ Verify Info.plist has no ATT permission string if not tracking
5. ✅ Run checklist from TESTFLIGHT_READINESS.md

---

## Key Learnings

1. **"Used for Tracking" is VERY specific**: Only check if you're doing cross-app/cross-site tracking for ads
2. **First-party analytics is NOT tracking**: Collecting usage data within your own app doesn't require ATT
3. **Support URL must be functional**: Can't be a placeholder or landing page
4. **Privacy labels must be precise**: Over-reporting data collection triggers unnecessary ATT requirements

---

## References

- [App Tracking Transparency Guidelines](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [Privacy Labels FAQ](https://developer.apple.com/app-store/app-privacy-details/)
- [User Privacy and Data Use](https://developer.apple.com/documentation/apptrackingtransparency)
