# Onboarding Experience - Completion Plan

## 📊 Current State Analysis

### ✅ What's Working (UI Complete)

#### **Views Implemented:**
1. ✅ **WelcomeView** - Entry point with Sign In / Create Account
2. ✅ **CreateAccountBottomSheet** - Email/OTP or Social sign-up
3. ✅ **SignInBottomSheet** - Email/OTP or Social sign-in
4. ✅ **OTPVerificationView** - 6-digit code verification
5. ✅ **CreateAccountView** - First name + Last name collection
6. ✅ **LearnAboutYourselfView** - Personalization text collection
7. ✅ **ThemesIdentifiedView** - Theme selection (6 themes)
8. ✅ **LoadingStateView** - Onboarding completion animation

#### **Backend Methods Implemented:**
1. ✅ `SupabaseService.updateUserMetadata()` - Save first/last name
2. ✅ `SupabaseService.updateUserPersonalization()` - Save personalization text
3. ✅ `SupabaseService.updateUserThemes()` - Save selected themes
4. ✅ `SupabaseService.completeUserOnboarding()` - Mark onboarding complete
5. ✅ `SupabaseService.hasCompletedOnboarding()` - Check onboarding status

#### **ViewModels Implemented:**
1. ✅ **OnboardingViewModel** - State management for onboarding data
2. ✅ **AuthViewModel** - Authentication and onboarding status
3. ✅ **OnboardingCoordinatorView** - Navigation flow coordination

---

## ❌ Current Problems

### **Problem #1: Inconsistent Entry Points**

**Issue:**
- **New users** (not authenticated) → Start at `WelcomeView` ✅
- **Existing users** (authenticated, incomplete onboarding) → Start at `OnboardingCoordinatorView` (skips WelcomeView) ❌

**Current Flow from withMementoApp.swift:**
```swift
if authViewModel.isAuthenticated {
    if authViewModel.hasCompletedOnboarding {
        // Show main app
        ContentView()
    } else {
        // Show onboarding flow - SKIPS WelcomeView
        OnboardingCoordinatorView()  // ❌ Starts at CreateAccountView
    }
} else {
    // Show welcome/login
    WelcomeView()  // ✅ Correct entry point
}
```

**Why This is Wrong:**
- Authenticated users who haven't completed onboarding skip the welcome experience
- They go directly to CreateAccountView which asks for first/last name
- But they've already created an account (they're authenticated!)
- This creates confusion and a broken UX

---

### **Problem #2: OnboardingCoordinatorView Starts at Wrong Step**

**Issue:**
OnboardingCoordinatorView always starts at CreateAccountView:

```swift
public var body: some View {
    NavigationStack(path: $navigationPath) {
        CreateAccountView(  // ❌ Always starts here
            onComplete: {
                handleProfileComplete()
            }
        )
        .environmentObject(authViewModel)
        // ...
    }
}
```

**Why This is Wrong:**
- If user is already authenticated (via Apple/Google Sign In), they already have an account
- They shouldn't see "CreateAccountView" asking for first/last name again
- They should skip straight to LearnAboutYourselfView

---

### **Problem #3: No Logic for Determining Current Step**

**Issue:**
No logic to determine where in the onboarding flow a user should resume.

**What Should Happen:**
1. User creates account (authenticated = true)
2. User adds first/last name → saved to `user_metadata.first_name/last_name`
3. User closes app
4. User reopens app
5. System should check:
   - ✅ Is authenticated?
   - ✅ Has first/last name? → Skip CreateAccountView
   - ❌ Has personalization text? → Resume at LearnAboutYourselfView
   - ❌ Has themes? → Resume at ThemesIdentifiedView
   - ❌ Has completed onboarding? → Resume at LoadingStateView

**Currently:** Always starts at CreateAccountView, no resume logic

---

### **Problem #4: WelcomeView Doesn't Navigate to Onboarding**

**Issue:**
WelcomeView has an `onNext` callback but it's never properly wired:

```swift
WelcomeView(onNext: {
    // Optional: handle "Get Started" if you want onboarding
})
```

**Why This is Wrong:**
- After successful sign-in/sign-up from WelcomeView, nothing happens
- The bottom sheets have `onSignUpSuccess` and `onSignInSuccess` callbacks
- These callbacks dismiss the sheet and call `onNext?()`
- But `onNext` is an empty closure that does nothing

---

### **Problem #5: Social Sign-In Users Skip Profile Step**

**Issue:**
When users sign in with Apple/Google:
- They're automatically authenticated
- Apple/Google may provide first/last name
- But this data isn't consistently saved to `user_metadata`
- So when they reach CreateAccountView, it asks for their name again

**Current Code:**
```swift
// CreateAccountBottomSheet.swift
private func signUpWithAppleNative() {
    // ... Apple auth code
    if let error = errorMessage {
        self.appleNativeError = error
    } else {
        // Success - dismiss sheet
        self.dismiss()
        self.onSignUpSuccess?()  // ❌ Just dismisses, doesn't save name
    }
}
```

**Missing:**
- Extract first/last name from Apple ID credential
- Save to `user_metadata` via `SupabaseService.updateUserMetadata()`
- Then navigate to next step

---

### **Problem #6: Email/OTP Flow Doesn't Return to Onboarding**

**Issue:**
After OTP verification:

```swift
// OTPVerificationView.swift
if authViewModel.isAuthenticated {
    // Authentication successful - dismiss
    dismiss()  // ❌ Returns to WelcomeView, not onboarding
}
```

**Why This is Wrong:**
- User verifies OTP → becomes authenticated
- View dismisses back to WelcomeView
- But they should continue to CreateAccountView (first/last name)

---

## 🎯 Solution: Centralized Onboarding Flow

### **Goal:**
**ALL users (new and existing) should start at WelcomeView and follow a consistent flow based on their completion status.**

---

## 📋 Complete Implementation Plan

### **Phase 1: Fix withMementoApp Entry Point**

**Goal:** ALL users start at WelcomeView, then route based on state

**Current Code (Wrong):**
```swift
if authViewModel.isAuthenticated {
    if authViewModel.hasCompletedOnboarding {
        ContentView()
    } else {
        OnboardingCoordinatorView()  // ❌ Wrong
    }
} else {
    WelcomeView()
}
```

**New Code (Correct):**
```swift
if authViewModel.isAuthenticated && authViewModel.hasCompletedOnboarding {
    // Fully onboarded - show main app
    ContentView()
        .environmentObject(authViewModel)
} else {
    // Not authenticated OR incomplete onboarding - show WelcomeView
    WelcomeView()
        .useTheme()
        .useTypography()
        .environmentObject(authViewModel)
}
```

**Why This Works:**
- Not authenticated → WelcomeView (sign in/create account)
- Authenticated but incomplete onboarding → WelcomeView (will route to correct step)
- Authenticated AND complete onboarding → ContentView (main app)

---

### **Phase 2: Update WelcomeView to Handle Authenticated Users**

**Goal:** WelcomeView should detect if user is authenticated and route them

**New Logic:**
```swift
// WelcomeView.swift
public var body: some View {
    NavigationStack {
        // ... existing UI
    }
    .onAppear {
        checkAuthenticationAndRoute()
    }
    .fullScreenCover(isPresented: $showOnboardingFlow) {
        OnboardingCoordinatorView()
            .environmentObject(authViewModel)
    }
}

private func checkAuthenticationAndRoute() {
    if authViewModel.isAuthenticated {
        // User is authenticated but hasn't completed onboarding
        // Route to onboarding flow
        showOnboardingFlow = true
    }
}
```

**Result:**
- New users → See WelcomeView UI
- Returning authenticated users → Automatically routed to OnboardingCoordinatorView

---

### **Phase 3: Smart Resume Logic in OnboardingCoordinatorView**

**Goal:** Determine which step to start based on completed data

**New Implementation:**
```swift
public var body: some View {
    NavigationStack(path: $navigationPath) {
        // Smart starting point based on completion status
        if onboardingViewModel.shouldStartAtProfile {
            CreateAccountView(onComplete: handleProfileComplete)
        } else if onboardingViewModel.shouldStartAtPersonalization {
            LearnAboutYourselfView(onComplete: handlePersonalizationComplete)
        } else if onboardingViewModel.shouldStartAtThemes {
            ThemesIdentifiedView(themes: onboardingViewModel.generateThemes(), onComplete: handleThemesComplete)
        } else {
            LoadingStateView(onComplete: handleOnboardingComplete)
        }
    }
    .task {
        await onboardingViewModel.loadCurrentState()
    }
}
```

**Add to OnboardingViewModel:**
```swift
@Published var hasProfile: Bool = false
@Published var hasPersonalization: Bool = false
@Published var hasThemes: Bool = false

var shouldStartAtProfile: Bool {
    !hasProfile
}

var shouldStartAtPersonalization: Bool {
    hasProfile && !hasPersonalization
}

var shouldStartAtThemes: Bool {
    hasProfile && hasPersonalization && !hasThemes
}

func loadCurrentState() async {
    // Check what data exists in Supabase
    do {
        let user = try await SupabaseService.shared.getCurrentUser()

        // Check for profile data
        let firstName = user?.userMetadata["first_name"] as? String
        let lastName = user?.userMetadata["last_name"] as? String
        hasProfile = firstName != nil && lastName != nil

        // Check for personalization
        let personalization = user?.userMetadata["user_personalization_text"] as? String
        hasPersonalization = personalization != nil && !personalization!.isEmpty

        // Check for themes
        let themes = user?.userMetadata["selected_themes"] as? [String]
        hasThemes = themes != nil && !themes!.isEmpty

    } catch {
        AppLogger.log("Error loading onboarding state: \(error)",
                     category: AppLogger.general,
                     type: .error)
    }
}
```

---

### **Phase 4: Fix Social Sign-In to Save Profile Data**

**Goal:** Extract and save name from Apple/Google sign-in

**Update CreateAccountBottomSheet:**
```swift
private func signUpWithAppleNative() {
    // ... existing code

    let delegate = AppleAuthDelegate(nonce: nonce) { [self] errorMessage in
        DispatchQueue.main.async {
            self.isLoadingAppleNative = false
            if let error = errorMessage {
                self.appleNativeError = error
            } else {
                // Success - extract name and save
                Task {
                    await self.handleAppleSignInSuccess()
                }
            }
        }
    }
}

private func handleAppleSignInSuccess() async {
    // Get user from Supabase
    guard let user = try? await SupabaseService.shared.getCurrentUser() else {
        return
    }

    // Check if first/last name already exist
    let firstName = user.userMetadata["first_name"] as? String
    let lastName = user.userMetadata["last_name"] as? String

    if firstName == nil || lastName == nil {
        // Name not saved - could extract from Apple ID or prompt user
        // For now, let them proceed to CreateAccountView
    }

    dismiss()
    onSignUpSuccess?()
}
```

---

### **Phase 5: Fix OTP Flow Navigation**

**Goal:** After OTP verification, navigate to correct onboarding step

**Update OTPVerificationView:**
```swift
private func verifyCode() {
    // ... existing verification code

    Task {
        do {
            try await authViewModel.verifyOTP(code: otpCode)

            await MainActor.run {
                isVerifying = false

                if authViewModel.isAuthenticated {
                    // Don't dismiss - let withMementoApp handle routing
                    // OR navigate to onboarding flow
                    // The key is DON'T return to WelcomeView
                }
            }
        } catch {
            // ... error handling
        }
    }
}
```

**Better Approach:**
Change OTP to be part of onboarding flow, not a standalone full-screen modal

---

### **Phase 6: Add Loading State to Check Onboarding Status**

**Goal:** Show loading screen while checking what step user needs

**Add to WelcomeView:**
```swift
@State private var isCheckingOnboardingStatus = true

var body: some View {
    Group {
        if isCheckingOnboardingStatus {
            LoadingView()  // Your modern loading view
        } else if authViewModel.isAuthenticated {
            // Navigate to onboarding
            OnboardingCoordinatorView()
        } else {
            // Show welcome UI
            welcomeUI
        }
    }
    .task {
        await checkOnboardingStatus()
    }
}

private func checkOnboardingStatus() async {
    if authViewModel.isAuthenticated {
        // Load what data exists
        await onboardingViewModel.loadCurrentState()
    }
    isCheckingOnboardingStatus = false
}
```

---

## 📊 Updated User Flows

### **Flow 1: New User → Email Sign-Up**
```
1. WelcomeView
2. Tap "Create Account"
3. CreateAccountBottomSheet appears
4. Enter email → Tap "Continue"
5. OTPVerificationView (full screen)
6. Verify code → Authenticated
7. withMementoApp detects authenticated + no onboarding
8. Shows WelcomeView → Auto-routes to OnboardingCoordinatorView
9. OnboardingCoordinatorView checks state → No profile data
10. Shows CreateAccountView (first/last name)
11. Save name → Navigate to LearnAboutYourselfView
12. Save personalization → Navigate to ThemesIdentifiedView
13. Save themes → Navigate to LoadingStateView
14. Complete onboarding → Navigate to ContentView (main app)
```

### **Flow 2: New User → Apple Sign-In**
```
1. WelcomeView
2. Tap "Create Account"
3. CreateAccountBottomSheet appears
4. Tap "Continue with Apple"
5. Apple auth → Authenticated
6. Extract name from Apple (if available) → Save to metadata
7. Dismiss sheet
8. withMementoApp detects authenticated + no onboarding
9. Shows WelcomeView → Auto-routes to OnboardingCoordinatorView
10. OnboardingCoordinatorView checks state:
    - If name exists: Skip to LearnAboutYourselfView
    - If name missing: Show CreateAccountView
11. Continue onboarding flow...
```

### **Flow 3: Returning User (Interrupted Onboarding)**
```
1. User previously authenticated, saved name, closed app
2. Reopen app
3. withMementoApp checks: Authenticated = YES, Onboarding = NO
4. Shows WelcomeView
5. WelcomeView.onAppear checks auth state
6. Detects authenticated → Auto-routes to OnboardingCoordinatorView
7. OnboardingCoordinatorView.loadCurrentState() runs
8. Detects: Has profile = YES, Has personalization = NO
9. Starts at LearnAboutYourselfView (skips CreateAccountView)
10. Continue from where they left off...
```

### **Flow 4: Fully Onboarded User**
```
1. User completed all onboarding
2. Reopen app
3. withMementoApp checks: Authenticated = YES, Onboarding = YES
4. Shows ContentView (main app) immediately
5. No WelcomeView, no OnboardingCoordinatorView
```

---

## 🔧 Implementation Checklist

### **Phase 1: Entry Point Fix**
- [ ] Update `withMementoApp.swift` logic
- [ ] Remove OnboardingCoordinatorView from top-level routing
- [ ] Ensure WelcomeView is shown for incomplete onboarding

### **Phase 2: WelcomeView Smart Routing**
- [ ] Add `@State var showOnboardingFlow: Bool`
- [ ] Add `checkAuthenticationAndRoute()` method
- [ ] Add `.fullScreenCover` for OnboardingCoordinatorView
- [ ] Test authenticated user auto-routing

### **Phase 3: Resume Logic**
- [ ] Add state properties to OnboardingViewModel:
  - [ ] `hasProfile: Bool`
  - [ ] `hasPersonalization: Bool`
  - [ ] `hasThemes: Bool`
- [ ] Add computed properties:
  - [ ] `shouldStartAtProfile`
  - [ ] `shouldStartAtPersonalization`
  - [ ] `shouldStartAtThemes`
- [ ] Implement `loadCurrentState()` method
- [ ] Update OnboardingCoordinatorView to use smart starting point
- [ ] Test resume from each step

### **Phase 4: Social Sign-In Profile Data**
- [ ] Update AppleAuthDelegate to extract name
- [ ] Save extracted name to `user_metadata`
- [ ] Handle Google Sign-In similarly
- [ ] Test that social sign-in users skip CreateAccountView if name exists

### **Phase 5: OTP Flow Integration**
- [ ] Option A: Make OTP part of navigation stack
- [ ] Option B: After OTP, don't dismiss, navigate to onboarding
- [ ] Test that OTP flow continues to onboarding

### **Phase 6: Loading States**
- [ ] Add loading state while checking onboarding status
- [ ] Show LoadingView during state check
- [ ] Ensure smooth transition to correct view

### **Phase 7: Testing**
- [ ] Test new user email flow end-to-end
- [ ] Test new user Apple Sign-In flow
- [ ] Test new user Google Sign-In flow
- [ ] Test interrupted onboarding (close app after each step)
- [ ] Test fully onboarded user
- [ ] Test edge cases (no internet, Supabase errors, etc.)

---

## 🚨 Critical Issues to Address

### **1. OTP Modal vs Navigation**
**Problem:** OTP is a `fullScreenCover` modal, so it dismisses back to WelcomeView

**Solution Options:**
- **Option A:** Make OTP part of OnboardingCoordinatorView navigation stack
- **Option B:** After OTP auth, manually navigate to OnboardingCoordinatorView
- **Option C:** Restructure to have all auth happen in WelcomeView, then transition

**Recommended:** Option C - Keep auth separate, then transition

---

### **2. First/Last Name from Social Sign-In**
**Problem:** Apple/Google may or may not provide name

**Solution:**
- Check if name exists in credential
- If yes: Save to metadata automatically
- If no: User must fill in CreateAccountView
- Either way, smart resume logic handles it

---

### **3. Supabase Metadata Structure**
**Current Keys:**
- `first_name`
- `last_name`
- `user_personalization_text`
- `selected_themes`
- `onboarding_completed`

**Verify These Exist:**
- [ ] Check SupabaseService methods use these exact keys
- [ ] Confirm Supabase database stores these in `user_metadata` JSON field
- [ ] Test that data persists across sessions

---

## 📝 Summary

### **Current State:**
- ✅ UI is 100% complete and looks great
- ❌ Logic is fragmented and inconsistent
- ❌ Different entry points for different users
- ❌ No resume logic for interrupted onboarding
- ❌ Social sign-in doesn't save profile data
- ❌ OTP flow doesn't navigate to onboarding

### **End Goal:**
- ✅ ALL users start at WelcomeView
- ✅ WelcomeView automatically routes authenticated users to onboarding
- ✅ OnboardingCoordinatorView resumes at correct step
- ✅ Social sign-in saves profile data when available
- ✅ Interrupted onboarding picks up where user left off
- ✅ Smooth, consistent experience for all paths

### **Effort Estimate:**
- **Phase 1-2:** 2-3 hours (Entry point + WelcomeView routing)
- **Phase 3:** 3-4 hours (Resume logic + state management)
- **Phase 4:** 2-3 hours (Social sign-in profile data)
- **Phase 5:** 1-2 hours (OTP flow fix)
- **Phase 6:** 1 hour (Loading states)
- **Phase 7:** 2-3 hours (Testing all flows)

**Total:** 11-16 hours to get onboarding to 100%

---

## 🎯 Next Step

**Start with Phase 1:** Fix the entry point in withMementoApp.swift to ensure all users start at WelcomeView. This is the foundation for all other fixes.
