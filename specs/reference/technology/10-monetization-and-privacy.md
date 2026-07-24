# Monetization, Privacy, and Entitlements

**Role in Memento:** the commercial layer, and the compliance surface that the entire positioning depends on.

---

## 1. The eligibility chain — read this first

Memento's zero-COGS architecture rests on a chain of conditions. Break any link and the economics change:

```
App Store Small Business Program enrollment
        ↓
Fewer than 2M first-time App Store downloads
        ↓
Approved PCC access application
        ↓
Free Private Cloud Compute inference
        ↓
~100% gross margin, no server tier
```

✅ **VERIFIED** (session 319): PCC has no token cost to the developer, a daily per-user limit (higher with iCloud+), and eligibility for apps under 2M downloads.

**REQ-MON-002: Small Business Program enrollment is mandatory** — not merely a commission benefit. It is the eligibility condition for the architecture.

🔴 **Week 1 action:** verify enrollment status and file the PCC application at the Apple developer site. Lead time unknown. This is the single longest-lead dependency in the whole plan.

---

## 2. Pricing context

| | Slate (competitor) | Memento (current plan) |
|---|---|---|
| Monthly | $7.99 | $9.99 |
| Annual | $59.99 | $79 |
| Trial | 1 month | TBD |

**Facts to reason from, not conclusions:**

- Marginal inference cost is ~zero for both. Neither app can justify price by COGS. The 97% gross margin projection from v1.3 is no longer a differentiator — it is the floor everyone competes from.
- Slate has demonstrated that consumers will pay a subscription for a zero-marginal-cost local app. That de-risks the model materially.
- Memento's feature surface is larger. A premium is defensible; a 25–33% premium is a specific claim about perceived value that should be tested, not assumed.
- **Annual-first presentation suits this product.** The value proposition is explicitly longitudinal — "a year from now this will know you." Leading with a monthly plan is a positioning mismatch with the core promise.

**DEC-004 (open):** final price and trial length. Blocks the paywall spec and App Store Connect configuration.

---

## 3. Free vs paid split

**REQ-MON-003:**

| Free, forever | Paid |
|---|---|
| Unlimited capture | Weekly reflections |
| Transcription | Monthly insights / Patterns |
| Timeline | Ask (chat) |
| Search | Personal Voice |
| **Export (Markdown + JSON)** | |

**The principle: never hold a user's own words hostage.** The words are theirs; the intelligence is the product. Export in particular must never be paywalled — it is the structural guarantee behind the entire trust proposition, and paywalling it would make every privacy claim ring hollow.

---

## 4. Implementation

**REQ-MON-001:** StoreKit 2 with RevenueCat for receipt validation and subscriber analytics.

**RevenueCat receives: purchase events and an anonymous identifier. Nothing else. Ever.**

- No journal content
- No transcripts
- No derived data (moods, topics, salience)
- No user text of any kind
- No custom attributes that could carry content

This is REQ-PRIV-001 and it is absolute. An agent adding "just a topic tag for cohort analysis" to a RevenueCat attribute has committed a P0 privacy violation.

---

## 5. Privacy label — target: Data Not Collected

**REQ-MON-004.** Target label: **Data Not Collected**.

🔴 **Contingency:** does RevenueCat's SDK trigger a collection disclosure for purchase data? Verify before shipping.

**If it does:** evaluate StoreKit 2 direct and accept the loss of subscriber analytics. **The label is worth more than the dashboard.** Slate ships with "Data Not Collected" and it is a meaningful part of why their launch resonated. Matching it removes an axis of comparison where Memento would otherwise lose.

**No analytics SDK, at all.** Study telemetry is collected manually via surveys and interviews (REQ-EVAL-005). This is slower and it is the price of the label.

---

## 6. The positioning claim — exact language

**REQ-POS-001 is a P0 defect class, not a marketing preference.**

### Permitted

> No account. No analytics. No third-party AI. Your words are processed on your iPhone, or on Apple's Private Cloud Compute, which stores nothing and is independently verifiable. Nothing else.

### Forbidden while any PCC routing is enabled

- ❌ "Nothing leaves your phone"
- ❌ "No network calls"
- ❌ "Turn on airplane mode and everything still works"
- ❌ "There is no server"

These are Slate's claims and they are true *for Slate*. If Memento uses PCC, they are false for Memento. Overstating the trust boundary is an existential brand risk — the kind of thing that gets an indie app torched publicly, permanently, in the exact community that would otherwise be its advocates.

**Note the strategic wrinkle:** if the forced-degradation cohort in the 30-day study (`04-evaluations.md` Gate 5) shows Z0-only satisfaction is close to Z1, Memento *could* ship on-device-only and make the absolute claim. That would be a major finding and it must be evaluated **before** marketing copy is locked, not after.

---

## 7. Entitlements checklist

Every entitlement Memento needs, with lead-time risk flagged:

| Entitlement | Lead time | Priority |
|---|---|---|
| **PCC access** (developer site application) | 🔴 Unknown | **Week 1** |
| **Journaling Suggestions** (request to Apple) | 🔴 Unknown | **Week 1** |
| CloudKit | None | Standard |
| HealthKit (read + write) | None, but review scrutiny | Phase 4 |
| WeatherKit | None, quota-limited | Phase 4 |
| Background modes: audio, processing | None | Phase 1 |
| Siri / App Intents | None | Phase 4 |
| Push (for local notifications only) | None | Phase 3 |

**The two unknowns at the top are calendar dependencies, not implementation details.** File both in week one, before any code is deleted.

---

## 8. App Review risk register

| Risk | Mitigation |
|---|---|
| **Personal Voice outside accessibility context** | 🔴 Verify posture before building the flow (`06-speech-and-audio.md` B3) |
| **HealthKit data in model prompts** | Conservative default: exclude entirely (DEC-006, `08-context-frameworks.md` §3) |
| **Paywall on non-Apple-Intelligence devices** | REQ-PLAT-004 — do not present a paywall for features the device cannot run. This is a refund event *and* a review rejection risk. |
| **Mental health framing** | NON-GOAL: no therapeutic advice, diagnosis, or treatment framing. Archivist persona, enforced by evaluation. |
| **Crisis content** | REQ-SUR-004 — static, respectful, region-appropriate resource card. Never generated counseling. Specified centrally, applies to every generative surface. |

The last two are the ones most likely to be underestimated. A journaling app with an AI that talks back sits close to a category Apple regulates carefully. The archivist persona is a safety architecture as much as a differentiation strategy — it is defensible precisely *because* the model never advises.

---

## 9. Launch timing

iOS 27 GA is roughly 8–10 weeks out. ✅ VERIFIED that production PCC support ships with iOS 27 this fall.

Aligning launch to iOS 27 GA is a deliberate distribution strategy: **Apple features apps that adopt new APIs at release.** Memento adopts Foundation Models, PCC, `SpotlightSearchTool`, App Intents entity schemas, Journaling Suggestions, and Liquid Glass. That is an unusually strong adoption story for an indie app, and it is distribution that cannot be purchased.

The iOS 27-only deployment target (REQ-PLAT-001) is therefore not only a technical requirement — it is part of the launch strategy.
