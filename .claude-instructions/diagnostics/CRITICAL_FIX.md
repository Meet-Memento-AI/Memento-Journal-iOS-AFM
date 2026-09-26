# 🚨 CRITICAL FIX: Complete Performance Optimization

## THE SIMPLEST SOLUTION
Remove ALL async work from init() and use onAppear instead.

## File 1: AuthViewModel.swift
Replace the entire init() with:
```swift
init() {
    // NO async work in init - instant creation
}
```

Add this NEW function:
```swift
func initializeAuth() async {
    await checkAuthState()
    await setupAuthObserver()
}
```

## File 2: withMementoApp.swift  
Add .task modifier:
```swift
WindowGroup {
    Group {
        if authViewModel.isAuthenticated {
            ContentView()
                .environmentObject(authViewModel)
        } else {
            WelcomeView()
                .environmentObject(authViewModel)
        }
    }
    .task {
        // Initialize auth AFTER UI renders
        await authViewModel.initializeAuth()
    }
}
```

## File 3: EntryViewModel.swift
Verify init is empty:
```swift
init() {
    // Don't load on init - prevents UI freeze
}
```

## File 4: JournalView.swift  
Replace .task with .onAppear:
```swift
.onAppear {
    Task {
        await entryViewModel.loadEntriesIfNeeded()
    }
}
```

This ensures:
1. AuthViewModel creates instantly
2. UI renders immediately
3. Auth check happens in background
4. EntryViewModel creates instantly  
5. Entry loading happens in background
