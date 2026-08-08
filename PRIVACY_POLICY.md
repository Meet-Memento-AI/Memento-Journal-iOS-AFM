# Privacy Policy for MeetMemento

> ## ⛔️ STALE — NOT THE PUBLISHED POLICY (flagged 2026-08-07)
>
> **The authoritative privacy policy is [`docs/privacy.html`](docs/privacy.html)**,
> which is what gets served to users and linked from App Store Connect.
>
> This markdown file has diverged from it and is **factually wrong about the
> current app**: it describes Google Gemini 2.5 Flash, a Supabase backend, and
> account-based data collection, none of which exist since
> `509b9f0 refactor: fully decommission Supabase; app is on-device only`.
> Publishing or citing it would be a Guideline 5.1.1(i) and 5.1.2(i) defect.
>
> Do not update this file to fix it — update `docs/privacy.html`, and either
> regenerate this from that or delete it. Tracked in
> [`docs/app-store/00-readiness-checklist.md`](docs/app-store/00-readiness-checklist.md) B2.
>
> **Separately:** the version currently *live* at
> `sebmendo1.github.io/MeetMemento/privacy.html` is a third, even older copy
> that still names OpenAI, Google, and Supabase — because GitHub Pages serves
> from a different repository. See
> [`docs/app-store/11-rejection-playbook.md`](docs/app-store/11-rejection-playbook.md) §1.

**Last Updated:** March 19, 2026 — **superseded, see banner above**

## Overview

MeetMemento ("we", "our", or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, and protect your personal information when you use our journaling app.

## Information We Collect

### Information You Provide
- **Account Information**: Email address, name (when you create an account via Apple Sign In, Google Sign In, or Email OTP)
- **Journal Content**: Your journal entries, titles, and any personalization data you provide
- **Usage Data**: Information about how you use the app (entry count, themes selected, onboarding completion)

### Automatically Collected Information
- **Authentication Data**: Login session tokens, authentication state
- **Technical Data**: Device type, OS version, app version (for debugging and support)

## How We Use Your Information

We use your information to:
- Provide and maintain the MeetMemento service
- Enable account creation and authentication
- Store and sync your journal entries across devices
- Generate AI-powered insights about your journaling patterns
- Improve our app and user experience
- Respond to support requests

## Data Storage and Security

### Where Your Data is Stored
- Your journal entries and account data are stored securely on Supabase (cloud infrastructure)
- Authentication is handled by Supabase Auth with industry-standard security
- All data is transmitted using HTTPS encryption

### How We Protect Your Data
- All data is encrypted in transit using HTTPS/TLS
- Your device PIN protects local app access
- Secure authentication with Apple Sign In, Google Sign In, or Email OTP
- Row-Level Security (RLS) ensures you can only access your own journal entries
- Regular security updates and monitoring

## AI-Powered Features

MeetMemento uses Google Gemini to power AI features including Chat and Insights.

### Google Gemini 2.5 Flash
- **Used for:** AI Chat, semantic search, and insights generation
- **Data sent:** Your messages and relevant journal entries when you use AI features
- **Processing:** Real-time processing only; your data is not stored by Google
- **Training:** Google does not use your data to train AI models (Gemini API data usage policy)

### Your Control
- You can disable AI features anytime in Settings > Data & Privacy
- When disabled, no journal data is sent to AI services
- You will be asked for consent before first use of AI features

## Data Sharing

We do **not** sell, rent, or share your personal information with third parties except:

- **Service Providers**: Supabase (hosting), Google Gemini (AI features), Apple/Google (authentication)
- **Legal Requirements**: If required by law, regulation, or valid legal process
- **Safety**: To protect the rights, property, or safety of MeetMemento, our users, or others

## Your Rights

You have the right to:
- **Access**: Request a copy of your personal data
- **Delete**: Delete your account and all associated data at any time via Settings > Delete Account
- **Correct**: Update your account information in Settings > Profile
- **Export**: Export your journal entries as JSON (coming soon)

## Data Retention

- Your journal entries are retained until you delete them or delete your account
- Deleted entries are permanently removed within 30 days
- Account deletion permanently removes all your data

## Children's Privacy

MeetMemento is not intended for children under 13. We do not knowingly collect information from children under 13. If you believe we have collected information from a child under 13, please contact us.

## Third-Party Services

MeetMemento integrates with:
- **Supabase** ([Privacy Policy](https://supabase.com/privacy)) - Cloud hosting and database
- **Google Gemini** ([Privacy Policy](https://policies.google.com/privacy)) - AI-powered chat and insights
- **Apple Sign In** ([Privacy Policy](https://www.apple.com/legal/privacy/)) - Authentication
- **Google Sign In** ([Privacy Policy](https://policies.google.com/privacy)) - Authentication

## Changes to This Policy

We may update this Privacy Policy from time to time. We will notify you of material changes by posting the new policy in the app or on our website. Your continued use after changes constitutes acceptance.

## Contact Us

If you have questions about this Privacy Policy or your data, contact us at:

**Email**: support@sebastianmendo.com
**Support**: In-app Settings > About > Support

## Your Consent

By using MeetMemento, you consent to this Privacy Policy.

---

**For App Review / TestFlight**: This app is a personal journaling tool designed to help users reflect on their thoughts and experiences. All user data is private and secured with industry-standard encryption and authentication.